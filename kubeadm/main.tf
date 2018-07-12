resource "digitalocean_ssh_key" "k8s_key" {
  name       = "k8s_key"
  public_key = "${file("k8s-key.pub")}"
}

resource "digitalocean_droplet" "k8s_master" {
  name     = "k8s-master-${count.index + 1}"
  image    = "${var.k8s_snapshot_id}"
  region   = "${var.region}"
  size     = "${var.k8s_master_size}"
  ssh_keys = ["${digitalocean_ssh_key.k8s_key.id}"]
  count    = "1"

  connection {
    type        = "ssh"
    user        = "root"
    private_key = "${file("k8s-key")}"
  }
}

resource "digitalocean_droplet" "worker" {
  name     = "worker-${count.index + 1}"
  image    = "${var.k8s_snapshot_id}"
  region   = "${var.region}"
  size     = "${var.worker_size}"
  ssh_keys = ["${digitalocean_ssh_key.k8s_key.id}"]
  count    = "${var.workers}"

  depends_on = ["digitalocean_droplet.k8s_master"]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = "${file("k8s-key")}"
  }
}

output "master-1-ip" {
  value = "${digitalocean_droplet.k8s_master.0.ipv4_address}"
}

output "worker-ip" {
  value = "${digitalocean_droplet.worker.*.ipv4_address}"
}
