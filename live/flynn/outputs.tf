output "configure_kubectl" {
  value = module.argocd_cluster.configure_kubectl
}

output "configure_argocd" {
  value = module.argocd_cluster.configure_argocd
}

output "access_argocd" {
  value = module.argocd_cluster.access_argocd
}
