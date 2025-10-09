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
  default = "packer-gce-envoy4"
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
      "sudo apt-get install -yq apt-transport-https ca-certificates curl gnupg lsb-release",
      "sudo mkdir -p /opt",
      "sudo touch /opt/hello.txt && sudo echo 'hello world' | sudo tee /opt/hello.txt && cat /opt/hello.txt",
      "echo 'Basic packages installed successfully'"
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
      "echo 'Envoy version check completed successfully'",
     
 
    ]
  }


  # validatation of accounts & permissions
  provisioner "shell" {
    inline = [
       "envoy --version",
       "gcloud --version",
       "gcloud auth list"
    ]
  }



  # gs://jason-hsbc_cloudbuild/envoyproxy/envoy.yaml 
  #download envoy config file from GCS bucket AND place it in /etc/envoy/envoy.yaml
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/envoy",
      "sudo gsutil cp gs://jason-hsbc_cloudbuild/envoyproxy/envoy.yaml /etc/envoy/envoy.yaml",
      "echo 'Envoy config file downloaded successfully'",
      "cat /etc/envoy/envoy.yaml"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo sh -c 'nohup envoy -c /etc/envoy/envoy.yaml > /var/log/envoy-output.log 2>&1 &'",
      "echo 'Envoy started successfully in background'",
      "ls -l /var/log/envoy-output.log",
      "cat /var/log/envoy-output.log",
    ]
  }

  provisioner "shell" {
    inline = [
      "ENVOY_PATH=$(which envoy)",
      "if [ -z \"$ENVOY_PATH\" ]; then echo 'Envoy executable not found!' && exit 1; fi",
      "echo \"$ENVOY_PATH\" | sudo tee /tmp/envoy_path.txt",
      "echo 'Envoy path saved to /tmp/envoy_path.txt'"
    ]
  }

  # Download envoy.service from GCS bucket
  provisioner "shell" {
    inline = [
      "sudo gsutil cp gs://jason-hsbc_cloudbuild/envoyproxy/envoy.service /etc/systemd/system/envoy.service",
      "echo 'Envoy systemd service file downloaded successfully'",
      "sudo cat /etc/systemd/system/envoy.service"
    ]
  }

  # 2. Install service (daemon-reload, enable)
  provisioner "shell" {
    inline = [
      "sudo systemctl daemon-reload",
      "sudo systemctl enable envoy",
      "echo 'Envoy systemd service reloaded and enabled'"
    ]
  }

  # 3. Start service
  provisioner "shell" {
    inline = [
      "sudo rm -f /dev/shm/envoy_shared_memory_0", # Clean up shared memory before starting Envoy
      "sudo touch /var/log/envoy.log", # Create log file
      "sudo chown envoy:envoy /var/log/envoy.log", # Set ownership for envoy user
      "sudo systemctl start envoy", # Start service
      "sleep 5", # Give Envoy time to start
      "echo 'Envoy systemd service started'"
    ]
  }

  # List Envoy service startup logs
  provisioner "shell" {
    inline = [
      "echo 'trying to list Envoy service startup logs:'",
       "echo '===============================/var/log/envoy-out.log==========================================='",
     "echo '==================================/var/log/envoy.log========================================='",
      "sudo cat /var/log/envoy.log", # List Envoy's custom log file
      "echo '==========================================================================='",
      "sudo journalctl -u envoy.service --no-pager --since \"5 minutes ago\"",
      "echo 'Envoy service startup logs listed'",
      "echo '==========================================================================='"
    ]
  }

  # 4. Check status
  provisioner "shell" {
    inline = [
      "sudo systemctl status envoy --no-pager",
      "echo 'Envoy systemd service status checked'"
    ]
  }



}
