resource "kind_cluster" "default" {
  name           = "todo-cluster-tf"
  node_image     = "kindest/node:v1.27.3"
  wait_for_ready = true
}

resource "kubernetes_namespace_v1" "todo-app" {
  metadata {
    name = "todo-app"
  }
}

resource "helm_release" "todo-app" {
  name             = "todo-app"
  chart            = "${path.module}/../../todo-app-helm"
  namespace        = kubernetes_namespace_v1.todo-app.metadata[0].name
  create_namespace = false
  atomic           = true # purge chart on fail
  values           = [file("${path.module}/../../todo-app-helm/values.yaml")]
  depends_on       = [kubernetes_namespace_v1.todo-app]
}
