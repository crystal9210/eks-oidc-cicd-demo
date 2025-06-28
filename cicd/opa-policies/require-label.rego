package kubernetes.admission

deny[msg] {
  input.request.kind.kind == "Deployment"
  not input.request.object.metadata.labels["team"]
  msg := "All deployments must have a 'team' label"
}
