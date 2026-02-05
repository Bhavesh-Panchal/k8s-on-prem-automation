#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Print each command before executing it
#set -x

# Step 0 remove kubeadm-join.txt  file
sudo rm -rf /home/admin/kubeadm-join.txt

# Step 1: Re-enable swap (Undo Step 14)
sudo sed -i '/\bswap\b/ s/^#//' /etc/fstab || true
sudo swapon -a || true

# Step 2: Remove kubeadm reset, continue if kubeadm is not found
sudo kubeadm reset -f || true

# Step 3: Unhold packages if they are held, continue if they aren't held
sudo apt-mark unhold kubelet kubeadm kubectl || true

# Step 4: Uninstall kubelet, kubeadm, and kubectl (Undo Steps 11-12), continue if they are not found
sudo apt-get remove --purge -y --allow-change-held-packages kubelet kubeadm kubectl || true
sudo apt-get autoremove -y || true

# Clean up Kubernetes related files
sudo rm -rf /etc/apt/keyrings/kubernetes-apt-keyring.gpg || true
sudo rm -rf /etc/apt/sources.list.d/kubernetes.list || true
sudo apt-get update || true

# Step 5: Stop and disable kubelet service (Undo Step 13)
sudo systemctl disable --now kubelet || true

# Step 6: Revert kernel settings (Undo Steps 4-5)
sudo rm /etc/sysctl.d/kubernetes.conf || true
sudo sysctl --system || true

# Step 7: Uninstall Docker Engine, CLI, and Containerd (Undo Steps 2-7), continue if they are not found
sudo systemctl stop docker containerd || true
sudo systemctl disable docker containerd || true
sudo apt-get remove --purge -y docker-ce docker-ce-cli containerd.io || true
sudo apt-get autoremove -y || true
sudo rm -rf /etc/docker /var/lib/docker || true
sudo rm -rf /etc/containerd /var/lib/containerd || true
sudo rm /etc/apt/sources.list.d/docker.list || true
sudo rm /usr/share/keyrings/docker-archive-keyring.gpg || true
sudo apt-get update || true

# Step 8: Remove any remaining Docker or Kubernetes configuration files
sudo rm -rf /etc/modules-load.d/containerd.conf || true

# Step 9: Remove user from Docker group (optional, only if it was added)
sudo deluser $USER docker || true

# Step 10: Remove KUBECONFIG from all system-wide files
sudo sed -i '/KUBECONFIG/d' /etc/profile || true
sudo sed -i '/KUBECONFIG/d' /etc/environment || true
sudo sed -i '/KUBECONFIG/d' /etc/bash.bashrc || true

# Step 11: Reload daemon and source the modified files
sudo systemctl daemon-reload || true
source /etc/profile || true
source /etc/environment || true
source /etc/bash.bashrc || true

# remove kubernetes config file
sudo rm -rf $HOME/.kube || true

# Step 12: Clean up unnecessary packages and dependencies
sudo apt-get autoremove -y || true
sudo apt-get clean || true
