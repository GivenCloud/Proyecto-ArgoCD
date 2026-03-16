resource "kubernetes_config_map" "db" {
  metadata {
    name = "db-config"
  }

  data = {
    DB_HOST = "db-service"
    DB_PORT = tostring(var.db_port)
    DB_NAME = var.db_name
  }
}

resource "kubernetes_deployment" "db" {
  metadata {
    name = "db-deployment"
    labels = {
      app = "db"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "db"
      }
    }

    template {
      metadata {
        labels = {
          app = "db"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = var.db_image

          port {
            container_port = var.db_port
          }

          readiness_probe {
            exec {
              command = ["/bin/sh", "-c", "exec pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" -h 127.0.0.1 -p 5432"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            failure_threshold     = 3
          }

          liveness_probe {
            exec {
              command = ["/bin/sh", "-c", "exec pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" -h 127.0.0.1 -p 5432"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
          }

          env {
            name  = "POSTGRES_DB"
            value = var.db_name
          }

          env {
            name  = "POSTGRES_USER"
            value = var.db_user
          }

          env {
            name  = "POSTGRES_PASSWORD"
            value = var.db_password
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "db" {
  metadata {
    name = "db-service"
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "db"
    }

    port {
      port        = var.db_port
      target_port = var.db_port
    }
  }
}
