# Proposal: ZOA boundary & Access observability (platform)

**Status:** Implemented on branch `feat/zoa-boundary-observability-platform` ([ROSAENG-68808](https://redhat.atlassian.net/browse/ROSAENG-68808))  
**Application EMF:** [rosa-seaplane-zoa `docs/observability.md`](https://github.com/openshift-online/rosa-seaplane-zoa/blob/main/docs/observability.md) and [`docs/design/boundary-observability-proposal.md`](https://github.com/openshift-online/rosa-seaplane-zoa/blob/main/docs/design/boundary-observability-proposal.md)

This document tracked **YACE**, **PrometheusRule**, **Grafana**, and **promtool** work in **rosa-seaplane**. EMF remains namespace **`ZOA`** only.

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

## What shipped

### YACE

- **EMF job `zoa`**: `Reaper*`, `IdentityBridgeLookup` (plus existing TA/API/worker metrics).
- **Access Lambda**: static `AWS/Lambda` scrape for `{cluster_name}-zoa-access` on RC.
- **ECS Container Insights** (RC + MC): discovery on boundary cluster tags (`Component=zoa`, `Cluster=<cluster_id>`); metric **`TaskCount` Maximum** only.
- **Not shipped**: `PendingTaskCount` — [AWS documents](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html) it only with **`ServiceName` + `ClusterName`**; boundary uses **RunTask** without ECS services, and dev accounts showed **zero** `PendingTaskCount` series.

### Recording rules

| Record                                                          | Status  |
| --------------------------------------------------------------- | ------- |
| `zoa:reaper_last_run`, `zoa:reaper_tick_count`                  | Shipped |
| `zoa:access_availability`                                       | Shipped |
| `zoa:identity_bridge_hit_rate`                                  | Shipped |
| `zoa:lambda_error_rate` (includes Access in ratio)              | Shipped |

### Alerts

| Alert                                                                 | Status  |
| --------------------------------------------------------------------- | ------- |
| `ZOAReaperStalled`, `ZOAReaperErrors`                                 | Shipped |
| `ZOAAccessAvailabilityBelowSLO`                                       | Shipped |
| `ZOAIdentityBridgeHitRateBelowSLO`                                    | Shipped |
| `ZOALambdaErrorRateHigh` / throttling (Access in scope where scraped) | Shipped |

Runbook annotations reference current Grafana section names (**ZOA HTTP API**, **ZOA Access & Boundary**, **ZOA Workers**).

### Grafana

Dashboard reorganized with **ZOA**-prefixed sections; SLO row includes Access availability and identity-bridge hit rate; identity-bridge panels live under **ZOA HTTP API**; **Boundary running tasks** uses full-width ECS `TaskCount`.

### promtool

`ci/promtool-test/zoa-rules_test.yaml` covers recording rules (including reaper and bridge), SLO alerts, and updated runbook strings. Run **`make promtool-test`** before merge.

---

## Metric scope (unchanged design intent)

| Signal                                           | `$cluster` dropdown                           |
| ------------------------------------------------ | --------------------------------------------- |
| TA / API / worker / bridge ECS / identity bridge | Filters to selected RC/MC infra id            |
| Access HTTP (session routes)                     | `dimension_Cluster` = target id when filtered |
| Access availability **SLO stat**                 | **Not** filtered — regional Access deployment |
| Access deployment routes                         | Shown without MC-only filter                  |

---

## References

- [ZOA architecture observability](./zoa-architecture.md#observability)
- [alerting-architecture.md](./alerting-architecture.md)
- Worker reaper: rosa-seaplane-zoa [session-reaper.md](https://github.com/openshift-online/rosa-seaplane-zoa/blob/main/docs/boundary/session-reaper.md)
