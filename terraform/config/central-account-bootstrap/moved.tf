# States from before the CodePipeline rework hold the provisioner under its old
# address; map it to the provider-only module so its resources can be destroyed.
moved {
  from = module.pipeline_provisioner
  to   = module.platform_image_builder
}

moved {
  from = module.pipeline_notifications
  to   = module.codebuild_notifications
}

# The shared MC role is now always present instead of conditionally counted.
moved {
  from = aws_iam_role.mc_codebuild_role[0]
  to   = aws_iam_role.mc_codebuild_role
}

moved {
  from = aws_iam_role_policy.mc_codebuild_policy[0]
  to   = aws_iam_role_policy.mc_codebuild_policy
}
