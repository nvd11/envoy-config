                                                                                                                                                                                                                                                                                                                                     packer {
  required_plugins {
    googlecompute = {
      version = "~> 1.1"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "image_name" {
  type    = string
  default = "packer-gce-envoy"
}

variable "image_family" {
  type    = string
  default = "packer-gce"
}

# what packer will build here is a OS image for GCE, why sepecify network and subnetwork? just because we need it to install some packages from internet in next step
source "googlecompute" "default" {
  project_id   = "jason-hsbc"
  zone         = "europe-west2-c"
  image_name   = "${var.image_name}"
  image_family = "${var.image_family}"
  source_image_family = "debian-11"
  network = "projects/jason-hsbc/global/networks/tf-vpc0"
  subnetwork = "projects/jason-hsbc/regions/europe-west2/subnetworks/tf-vpc0-subnet0"
  ssh_username = "packer"
}

  build {
  sources = ["source.googlecompute.default"]

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "sudo apt-get update",
      "sudo apt-get install -yq vim",
      "sudo apt-get install -yq apt-transport-https ca-certificates curl gnupg lsb-release"
    ]
  }

# install envoy
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/apt/keyrings",
       "wget -O- https://apt.envoyproxy.io/signing.key | sudo gpg --dearmor -o /etc/apt/keyrings/envoy-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/envoy-keyring.gpg] https://apt.envoyproxy.io bullseye main\" | sudo tee /etc/apt/sources.list.d/envoy.list",
      "sudo apt-get update",
      "sudo apt-get install -yq envoy",
      "echo 'Envoy installed successfully'",
      "envoy --version",
      "echo 'Envoy version check completed successfully'"
    ]
  }

}
