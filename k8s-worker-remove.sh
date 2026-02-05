#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e 

# Print each command before executing it
#set -x

# Step 0 remove kubeadm-join.txt  file
sudo rm -rf /home/admin/kubeadm-join.txt || true

# Step 1: Re-enable swap (Undo Step 14)

sudo sed -i '/\bswap\b/ s/^#//' /etc/fstab || true
sudo swapon -a || true

# Step 2: remove kubeadm reset
sudo kubeadm reset -f || true

# Step 2: Unhold packages if they are held
sudo apt-mark unhold kubelet kubeadm kubectl || true

# Step 3: Uninstall kubelet, kubeadm, and kubectl (Undo Steps 11-12)
sudo apt-get remove --purge -y --allow-change-held-packages kubelet kubeadm kubectl || true
sudo apt-get autoremove -y || true

# Clean up Kubernetes related files
sudo rm -rf /etc/apt/keyrings/kubernetes-apt-keyring.gpg || true
sudo rm -rf /etc/apt/sources.list.d/kubernetes.list || true
sudo apt-get update || true

# Step 4: Stop and disable kubelet service (Undo Step 13)
#sudo systemctl disable --now kubelet

# Step 5: Revert kernel settings (Undo Steps 4-5)
sudo rm /etc/sysctl.d/kubernetes.conf || true
sudo sysctl --system || true

# Step 6: Uninstall Docker Engine, CLI, and Containerd (Undo Steps 2-7)
sudo systemctl stop docker containerd || true
sudo systemctl disable docker containerd || true
sudo apt-get remove --purge -y docker-ce docker-ce-cli containerd.io || true
sudo apt-get autoremove -y || true
sudo rm -rf /etc/docker /var/lib/docker || true
sudo rm -rf /etc/containerd /var/lib/containerd || true
sudo rm /etc/apt/sources.list.d/docker.list || true
sudo rm /usr/share/keyrings/docker-archive-keyring.gpg || true  
sudo apt-get update || true

# Step 7: Remove any remaining Docker or Kubernetes configuration files
sudo rm -rf /etc/modules-load.d/containerd.conf || true

# Step 8: Remove user from Docker group (optional, only if it was added)
sudo deluser $USER docker || true

# Step 9: Reload daemon
sudo systemctl daemon-reload || true

# Step 10: Clean up unnecessary packages and dependencies
sudo apt-get autoremove -y || true
sudo apt-get clean || true
