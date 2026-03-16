resource "kubernetes_deployment" "web" {
  metadata {
    name = "web-deployment"
    labels = {
      app = "web-server"
    }
  }

  spec {
    replicas = var.web_replicas

    selector {
      match_labels = {
        app = "web-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "web-server"
        }
      }

      spec {
        image_pull_secrets {
          name = "ghcr-secret"
        }

        container {
          name              = "web-server"
          image             = var.web_image
          image_pull_policy = var.web_image_pull_policy

          port {
            container_port = var.web_port
          }

          env {
            name  = "DB_HOST"
            value = "db-service"
          }

          env {
            name  = "DB_PORT"
            value = tostring(var.db_port)
          }

          env {
            name  = "DB_NAME"
            value = var.db_name
          }

          env {
            name  = "DB_USER"
            value = var.db_user
          }

          env {
            name  = "DB_PASSWORD"
            value = var.db_password
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = var.web_port
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = var.web_port
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "web" {
  metadata {
    name = "web-service"
  }

  spec {
    type = "NodePort"

    selector = {
      app = "web-server"
    }

    port {
      port        = 80
      target_port = var.web_port
      node_port   = var.web_node_port
    }
  }
}
