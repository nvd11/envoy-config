#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -yq vim
sudo apt-get install -yq apt-transport-https ca-certificates curl gnupg lsb-release
sudo mkdir -p /opt
sudo touch /opt/hello.txt && sudo echo 'hello world' | sudo tee /opt/hello.txt && cat /opt/hello.txt
echo 'Basic packages installed successfully'

sudo mkdir -p /etc/apt/keyrings
wget -O- https://apt.envoyproxy.io/signing.key | sudo gpg --dearmor -o /etc/apt/keyrings/envoy-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/envoy-keyring.gpg] https://apt.envoyproxy.io bullseye main" | sudo tee /etc/apt/sources.list.d/envoy.list
sudo apt-get update
sudo apt-get install -yq envoy
echo 'Envoy installed successfully'
envoy --version
echo 'Envoy version check completed successfully'

envoy --version
gcloud --version
gcloud auth list

sudo mkdir -p /etc/envoy
sudo gsutil cp gs://jason-hsbc_cloudbuild/envoyproxy/envoy.yaml /etc/envoy/envoy.yaml
echo 'Envoy config file downloaded successfully'
cat /etc/envoy/envoy.yaml

sudo sh -c 'nohup envoy -c /etc/envoy/envoy.yaml > /var/log/envoy-output.log 2>&1 &'
echo 'Envoy started successfully in background'
ls -l /var/log/envoy-output.log
cat /var/log/envoy-output.log

ENVOY_PATH=$(which envoy)
if [ -z "$ENVOY_PATH" ]; then echo 'Envoy executable not found!' && exit 1; fi
echo "$ENVOY_PATH" | sudo tee /tmp/envoy_path.txt
echo 'Envoy path saved to /tmp/envoy_path.txt'

sudo gsutil cp gs://jason-hsbc_cloudbuild/envoyproxy/envoy.service /etc/systemd/system/envoy.service
echo 'Envoy systemd service file downloaded successfully'
sudo cat /etc/systemd/system/envoy.service

sudo systemctl daemon-reload
sudo systemctl enable envoy
echo 'Envoy systemd service reloaded and enabled'

sudo rm -f /dev/shm/envoy_shared_memory_0 # Clean up shared memory before starting Envoy
sudo touch /var/log/envoy.log # Create log file
sudo chown envoy:envoy /var/log/envoy.log # Set ownership for envoy user
sudo systemctl start envoy # Start service
sleep 5 # Give Envoy time to start
echo 'Envoy systemd service started'

echo 'trying to list Envoy service startup logs:'
echo '===============================/var/log/envoy-out.log==========================================='
echo '==================================/var/log/envoy.log========================================='
sudo cat /var/log/envoy.log # List Envoy's custom log file
echo '==========================================================================='
sudo journalctl -u envoy.service --no-pager --since "5 minutes ago"
echo 'Envoy service startup logs listed'
echo '==========================================================================='

sudo systemctl status envoy --no-pager
echo 'Envoy systemd service status checked'
