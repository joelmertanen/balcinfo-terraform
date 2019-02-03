provider "google" {
  credentials = "${file("google_cloud_service_account.json")}"
  project     = "${var.project_name}"
  region      = "${var.region}"
  zone        = "${var.region}-a"
}

resource "google_compute_address" "static" {
  name         = "${var.local_project}-ip"
  network_tier = "PREMIUM"
}

resource "google_dns_managed_zone" "prod" {
  name        = "${var.local_project}-zone"
  dns_name    = "${var.domain_name}."
  description = "Production DNS zone"
}

resource "google_dns_record_set" "grafana" {
  name = "grafana.${google_dns_managed_zone.prod.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = "${google_dns_managed_zone.prod.name}"

  rrdatas = ["${google_compute_instance.appserver.network_interface.0.access_config.0.nat_ip}"]
}

resource "google_dns_record_set" "influx" {
  name = "grafana.${google_dns_managed_zone.prod.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = "${google_dns_managed_zone.prod.name}"

  rrdatas = ["${google_compute_instance.appserver.network_interface.0.access_config.0.nat_ip}"]
}

resource "random_id" "instance_id" {
  byte_length = 8
}

resource "google_compute_instance" "appserver" {
  name         = "appserver-${random_id.instance_id.hex}"
  machine_type = "g1-small"
  zone         = "${var.region}-a"

  metadata {
    sshKeys = "ubuntu:${file(var.ssh_key_path)}"
  }

  network_interface {
    network = "default"

    access_config {
      network_tier = "PREMIUM"
      nat_ip       = "${google_compute_address.static.address}"
    }
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1804-lts"
    }
  }

  attached_disk {
    source = "${var.local_project}-data"
    mode   = "READ_WRITE"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = "${file(replace(var.ssh_key_path, ".pub", ""))}"
  }

  // set up docker repo
  provisioner "remote-exec" {
    inline = [
      "echo | sudo -S apt-get update",
      "sudo apt-get install -yq apt-transport-https gnupg-agent software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"",
      "sudo apt-get update",
    ]
  }

  // install docker
  provisioner "remote-exec" {
    inline = [
      "echo | sudo -S apt-get install -yq build-essential docker-ce docker-compose docker-ce-cli containerd.io",
      "sudo usermod -aG docker ubuntu",
    ]
  }

  provisioner "file" {
    content     = "${var.google_cloud_service_account}"
    destination = "/home/ubuntu/google_cloud_service_account.json"
  }

  // install gcloud
  provisioner "remote-exec" {
    inline = [
      "mkdir /home/ubuntu/service",
      "mkdir /home/ubuntu/certs",
      "mv /home/ubuntu/google_cloud_service_account.json /home/ubuntu/certs",
      "docker pull google/cloud-sdk:latest",
      <<EOF
docker run -ti \
-v `pwd`/certs:/certs \
-v `pwd`/service:/service \
google/cloud-sdk:latest /bin/bash -c \
"gcloud auth activate-service-account ${var.service_account_email} --key-file=/certs/google_cloud_service_account.json --project=${var.project_name} &&
cd /service &&
gsutil cp gs://backend-storage/docker-compose.yml gs://backend-storage/.env.encrypted . &&
gcloud kms decrypt --location global --keyring storage --key storage --plaintext-file .env  --ciphertext-file .env.encrypted"
EOF
      ,
      "rm -rf certs",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "echo | sudo -S ls && echo \"/dev/sdb	/data	ext4	defaults	0	0\" | sudo tee -a /etc/fstab",
      "sudo mkdir /data",
      "sudo mount -a",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "cd /home/ubuntu/service",
      "docker-compose up -d",
    ]
  }

  provisioner "remote-exec" {
    when = "destroy"

    inline = [
      "cd /home/ubuntu/service",
      "docker-compose down",
    ]
  }

  provisioner "remote-exec" {
    when = "destroy"

    inline = [
      "echo | sudo -S umount /data",
    ]
  }
}
