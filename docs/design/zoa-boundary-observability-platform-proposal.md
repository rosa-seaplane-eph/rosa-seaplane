# Proposal: ZOA boundary & Access observability (platform)

**Status:** Draft (design only — no implementation in this branch)  
**Tracking:** [ROSAENG-68808](https://redhat.atlassian.net/browse/ROSAENG-68808)  
**Application code:** [rosa-seaplane-zoa boundary observability proposal](https://github.com/openshift-online/rosa-seaplane-zoa/blob/main/docs/design/boundary-observability-proposal.md) (EMF emitters; fork branch `feat/zoa-boundary-observability` until merged)

This document covers **YACE**, **Prometheus recording rules**, **alerting rules**, and **Grafana** changes in **rosa-seaplane**. All EMF remains in CloudWatch namespace **`ZOA`** — no new custom namespace.

---

## Source of truth files

| Artifact       | Path                                                               |
| -------------- | ------------------------------------------------------------------ |
| YACE RC        | `argocd/config/regional-cluster/cloudwatch-exporter/values.yaml`   |
| YACE MC        | `argocd/config/management-cluster/cloudwatch-exporter/values.yaml` |
| PrometheusRule | `argocd/config/regional-cluster/alerting-rules/templates/zoa.yaml` |
| Grafana        | `argocd/config/regional-cluster/grafana/dashboards/zoa/zoa.json`   |
| promtool tests | `ci/promtool-test/zoa-rules_test.yaml`                             |
| EMF catalog    | rosa-seaplane-zoa `docs/observability.md`                          |

---

## Metric scope: global vs per-VPC

Grafana variable **`$cluster`** today maps to **EKS cluster id** (RC regional id or `mc01`, …) and YACE **`dimension_Cluster`** on EMF for API/Worker.

| Signal                                      | Scope                                         | `$cluster` / filter                                                                                                     | Where in UI                                                 |
| ------------------------------------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Access HTTP EMF                             | **Per deployment** (one Access Lambda per RC) | **`DEPLOYMENT_NAME`** (or chosen deployment label in EMF) — **same value when user picks RC or any MC** in a deployment | **New section: Access & boundary sessions**                 |
| Access Lambda (`AWS/Lambda` `*-zoa-access`) | Per deployment (RC account)                   | Function name / tags; visible regardless of MC selection                                                                | Same section                                                |
| Identity bridge EMF                         | **Per API VPC** (RC + each MC)                | `dimension_Cluster` = target cluster id                                                                                 | Sub-panel under Access & boundary **or** Worker/API context |
| Reaper tick EMF                             | **Per target VPC**                            | `dimension_Cluster` = worker’s `TARGET_CLUSTER`                                                                         | **Worker Pipeline** (extend existing)                       |
| ECS `RunningTaskCount`                      | **Per target VPC**                            | ECS cluster `{cluster_id}-zoa-boundary`; YACE tag `Cluster=<cluster_id>`                                                | Access & boundary **per-VPC row** (follows `$cluster`)      |
| TA / API HTTP (existing)                    | Per API VPC                                   | Existing `$cluster`                                                                                                     | Existing sections                                           |

**Important:** When an operator selects **`mc01`** on the dashboard, **Access** panels should still show data (deployment-global). Use PromQL that does **not** filter Access series on `$cluster=mc01` only — e.g. separate variable `$deployment` or fixed deployment label from datasource context. Document in dashboard description.

**Reaper placement:** Reaper runs inside **Worker Lambda** (EventBridge route `reaper`, ~5m). It is **not** part of Access. UI:

- **Worker Pipeline** — add reaper duration, errors, last run, tick health (mirror GC).
- **Access & boundary sessions** — ECS running tasks, Access HTTP, session start SLO, identity bridge outcomes — **not** reaper tick panels (cross-link in panel description only).

---

## YACE changes

### 1. Custom namespace `ZOA` (RC + MC jobs)

Add to existing `customNamespace` list (same job `name: zoa`, `namespace: ZOA`):

| Metric                 | Statistics                  | Period notes                                  |
| ---------------------- | --------------------------- | --------------------------------------------- |
| `ReaperDuration`       | Average, p99                | 120s                                          |
| `ReaperErrors`         | Sum                         | 120s                                          |
| `ReaperLastRun`        | Maximum, `nilToZero: false` | **600s** (align GC / reaper schedule)         |
| `IdentityBridgeLookup` | Sum                         | 120s; filter in PromQL by `dimension_Outcome` |

After zoa repo adds Access HTTP with `HandlerMode=access`, existing `HttpRequestCount` / `HttpRequestDuration` scrape automatically lists new dimension sets — no metric name change.

### 2. New discovery job `AWS/ECS` (RC + MC)

Only **ZOA boundary** clusters — dedicated name `{global.cluster_name}-zoa-boundary`, tags from `terraform/modules/zoa-lambda/boundary-ecs.tf`:

```yaml
- type: AWS/ECS
  regions:
    - { { .Values.global.aws_region } }
  searchTags:
    - key: Component
      value: ^zoa$
    - key: Cluster
      value: ^{{ .Values.global.cluster_name }}$
  period: 120
  length: 120
  delay: 120
  metrics:
    - name: RunningTaskCount
      statistics: [Average, Maximum]
      nilToZero: true
    - name: PendingTaskCount
      statistics: [Maximum]
      nilToZero: true
```

Optional later: `CPUUtilization`, `MemoryUtilization` at cluster level.

**Do not** export per-task dimensions.

### 3. Lambda discovery (RC only for Access)

Extend alert/recording regexes from:

```regex
.*-zoa-(api|worker)
```

to:

```regex
.*-zoa-(api|worker|access)
```

Access function lives in **RC** account; MC YACE job may not see it — Access panels use RC datasource or Thanos series labeled with deployment.

---

## Recording rules (`zoa-recording-rules`)

Add (names illustrative; match existing style):

| Record                          | Intent                                                                                                          |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `zoa:reaper_last_run`           | `max by (cluster) (last_over_time(aws_zoa_reaper_last_run_maximum[10m]))`                                       |
| `zoa:reaper_tick_count`         | `changes(zoa:reaper_last_run[30m])` — 5m schedule → expect fewer changes than reconciler                        |
| `zoa:access_availability`       | Same formula as `zoa:api_availability` but `dimension_HandlerMode="access"` on `aws_zoa_http_request_count_sum` |
| `zoa:identity_bridge_miss_rate` | Optional: ratio of `Outcome=miss` to total lookups per cluster                                                  |

Keep **no** `active_sessions` recording rule.

---

## Alerts (`zoa-alerts`)

| Alert                              | Severity | Rationale                                                                            |
| ---------------------------------- | -------- | ------------------------------------------------------------------------------------ |
| `ZOAReaperStalled`                 | warning  | Mirror `ZOAGCStalled`; threshold **1800s** (6× 5m); three-path pattern like GC       |
| `ZOAReaperErrors`                  | warning  | Mirror `ZOAGCErrors`; `sum(aws_zoa_reaper_errors_sum) > 0`                           |
| `ZOAAccessAvailabilityBelowSLO`    | warning  | Uses `zoa:access_availability` + traffic guard                                       |
| `ZOAIdentityBridgeHitRateBelowSLO` | warning  | `zoa:identity_bridge_hit_rate` below target; skipped excluded; boundary volume guard |

Extend **`ZOALambdaErrorRateHigh`** / **`ZOALambdaThrottled`** to include `*-zoa-access` where series exist.

**Not adding:** “orphaned sessions”, “active session count”, arbitrary “5 alerts” quota from draft Jira.

Update **`ci/promtool-test/zoa-rules_test.yaml`** for new rules.

---

## Grafana dashboard (`zoa.json`)

### New top-level section: **Access & boundary sessions**

Suggested panels (order):

1. **Access HTTP availability** — stat from `zoa:access_availability` (deployment scope; note in description).
2. **Access request rate & latency** — `aws_zoa_http_request_count_sum{dimension_HandlerMode="access"}` by `RouteTemplate`; duration p99.
3. **Session operations** — bar chart filtered to routes: `sessions/start`, `join/{id}`, `terminate/{id}`, `exec-attached/{id}`.
4. **Access Lambda health** — `aws_lambda_*` for `*-zoa-access` (errors, duration, throttles).
5. **Identity bridge** — stacked `IdentityBridgeLookup` by `Outcome` per API `$cluster` (MC/RC API Lambdas).
6. **Boundary tasks (ECS)** — `aws_ecs_running_task_count_*` for cluster `$cluster-zoa-boundary` ( **follows `$cluster`** ).

Add dashboard variable if needed:

- **`$deployment`** — for Access-global panels (constant per Grafana datasource / annotation).

### Extend existing section: **Worker Pipeline**

Add rows (same layout as reconciler/GC):

- Reaper duration (avg/p99)
- Reaper errors (sum)
- Reaper last run / tick count (`zoa:reaper_last_run`, `zoa:reaper_tick_count`)

Do **not** duplicate reaper panels under Access.

### Existing sections

- **HTTP API** — remains TA API (`HandlerMode=api` or exclude access in legend).
- **Infrastructure Lambda** — optionally split legend api / worker / access.

---

## Ephemeral / multi-cluster accounts

Existing ServiceMonitor relabel drops `aws_zoa_*` where `dimension_Cluster` ≠ `global.cluster_name`. Access deployment metrics may need **parallel** relabel or separate job if multiple deployments share an account — document exception if Access EMF uses deployment id not EKS cluster name.

---

## Implementation order (platform)

1. YACE: reaper + bridge EMF names (after zoa emits).
2. Recording + reaper stall alert + Worker Pipeline panels.
3. Access availability + Lambda regex + Access section (after Access HTTP EMF).
4. Identity bridge alert + panel (after bridge EMF).
5. ECS job + RunningTaskCount panel.
6. promtool + dashboard JSON review in ephemeral.

---

## References

- Existing ZOA observability ADR table: [zoa-architecture.md](./zoa-architecture.md#observability)
- [alerting-architecture.md](./alerting-architecture.md)
- Worker reaper: rosa-seaplane-zoa [session-reaper.md](https://github.com/openshift-online/rosa-seaplane-zoa/blob/main/docs/boundary/session-reaper.md)
