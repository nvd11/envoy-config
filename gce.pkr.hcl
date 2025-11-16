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
    script = "scripts/setup_envoy.sh"
  }
}
