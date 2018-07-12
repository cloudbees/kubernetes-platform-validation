variable "token" {
  default = ""
}

variable "region" {
  default = "nyc3"
}

variable "k8s_master_size" {
  default = "s-2vcpu-4gb"
}

variable "worker_size" {
  default = "s-2vcpu-4gb"
}

variable "workers" {
  default = "2"
}

variable "k8s_snapshot_id" {}
