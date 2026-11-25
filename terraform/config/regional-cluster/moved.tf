# ZOA Lambda was previously optional via count on module.zoa_lambda (integration/stage
# state may still use module.zoa_lambda[0].*). #853 removed count so the module is
# always provisioned; this block renames state addresses without destroy/create in AWS.
moved {
  from = module.zoa_lambda[0]
  to   = module.zoa_lambda
}

# Installer-role resources are unconditional; preserve addresses from the opt-in PoC.
moved {
  from = aws_iam_role.platform_api[0]
  to   = aws_iam_role.platform_api
}

moved {
  from = aws_iam_role.installer_jump[0]
  to   = aws_iam_role.installer_jump
}

moved {
  from = aws_iam_role_policy.platform_api_account_access[0]
  to   = aws_iam_role_policy.platform_api_account_access
}

moved {
  from = aws_iam_role_policy.installer_jump[0]
  to   = aws_iam_role_policy.installer_jump
}

moved {
  from = aws_eks_pod_identity_association.platform_api[0]
  to   = aws_eks_pod_identity_association.platform_api
}
