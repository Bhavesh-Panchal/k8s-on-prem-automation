#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Print each command before executing it
#set -x

# Step 1: Configure persistent loading of modules
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

# Step 2: Install Docker

# Update package list
sudo apt-get update

# Install required packages
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker’s official repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package list again
sudo apt-get update

# Install Docker Engine
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Verify Docker installation
sudo docker --version

# Add your user to the docker group (optional)
sudo usermod -aG docker $USER

# Step 3: Load at runtime
sudo modprobe overlay
sudo modprobe br_netfilter

# Step 4: Update ip-tables
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Step 5: Applying kernel settings without reboot
sudo sysctl --system

# Step 6: Configure containerd for Systemd Cgroup Management
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Step 7: Reload Daemon, Restart, Enable, and Check containerd Service Status
sudo systemctl daemon-reload
sudo systemctl restart containerd 
sudo systemctl enable containerd 
sudo systemctl status containerd --no-pager

# Step 8: Update apt package index and install packages needed for Kubernetes HTTPS certificate configuration
sudo apt-get update && sudo sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Path to the version file
VERSION_FILE="/home/admin/selected_k8s_version.txt"

# Check if the file exists and read the Kubernetes version
if [[ -f "$VERSION_FILE" ]]; then
    K8S_VERSION=$(cat "$VERSION_FILE")
    echo "Using the selected Kubernetes version: $K8S_VERSION"
else
    echo "Error: The selected Kubernetes version file does not exist."
    exit 1
fi

# Adjust version format to two-digit for URL
VERSION_FORMATTED=$(echo "$K8S_VERSION" | sed 's/^\([0-9]*\.[0-9]*\).*$/\1/')

# Add the Kubernetes repository to the system’s package sources
echo "Selected Kubernetes version: $K8S_VERSION"

# Step 7: Add the Kubernetes repository to the system’s package sources
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${VERSION_FORMATTED}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${VERSION_FORMATTED}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Step 12: Install kubelet, kubeadm, and kubectl packages
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl

# Step 13: Hold the installed packages at their current versions
sudo apt-mark hold kubelet kubeadm kubectl

# Step 14: Enable the kubelet service on all nodes
sudo systemctl enable --now kubelet

# Step 15: Permanently disable swap
sudo swapoff -a
sudo sed -i.bak '/\bswap\b/ s/^\(.*\)$/#\1/' /etc/fstab
sudo swapon --show

# Verify that swap is disabled
sudo free -h

# Step 16: setup kubeadm join command
sudo bash -c "$(cat /home/admin/kubeadm-join.txt)"