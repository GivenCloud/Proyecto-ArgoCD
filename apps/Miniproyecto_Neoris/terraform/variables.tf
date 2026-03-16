variable "web_replicas" {
  default = 1
}

variable "web_image" {
  default = "ghcr.io/givencloud/miniproyecto_neoris:latest"
}

variable "web_image_pull_policy" {
  default = "Always"
}

variable "web_port" {
  default = 3000
}

variable "web_node_port" {
  default = 30080
}

variable "db_image" {
  default = "postgres:15-alpine"
}

variable "db_port" {
  default = 5432
}

variable "db_name" {
  default = "appdb"
}

variable "db_user" {
  default = "appuser"
}

variable "db_password" {
  default   = "apppassword"
  sensitive = true
}
