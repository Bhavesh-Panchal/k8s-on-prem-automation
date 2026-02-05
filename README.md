# K8s On-Prem Automation

A comprehensive bash-based automation toolkit for deploying and managing Kubernetes clusters on on-premise/bare-metal infrastructure.

## Overview

This toolkit provides a complete solution for setting up, managing, and removing Kubernetes clusters on bare-metal or virtualized environments. It supports multiple CNI plugins (Calico, Flannel, Weave Net), MetalLB load balancer integration, and automated worker node provisioning via SSH.

## Features

- **Automated Cluster Setup** - One-command Kubernetes cluster deployment
- **Multiple CNI Support** - Choose between Calico, Flannel, or Weave Net
- **MetalLB Integration** - Built-in LoadBalancer support for on-prem environments
- **Worker Node Auto-Provisioning** - Parallel SSH-based worker installation
- **Version Selection** - Install any Kubernetes version with automatic latest version detection
- **Complete Removal** - Clean uninstallation scripts for both master and worker nodes
- **Interactive Menu** - User-friendly menu-driven interface

## Prerequisites

- **Operating System**: Ubuntu Linux (tested on Ubuntu 20.04/22.04)
- **Hardware Requirements**:
  - Master Node: Minimum 2 CPU, 2GB RAM
  - Worker Node: Minimum 1 CPU, 1GB RAM
- **Network**: All nodes must be able to communicate with each other
- **Access**: Root or sudo privileges on all nodes

## Quick Start

### 1. Master Node Preparation

First, prepare the master node by running the prerequisite script:

```bash
chmod +x k8s-master-prerequisite.sh
sudo ./k8s-master-prerequisite.sh
```

This script will:
- Create an `admin` user with password `ubuntu`
- Grant sudo privileges without password
- Generate SSH keys for the `admin` user
- Prompt for worker node count and IP addresses
- Copy SSH keys to all worker nodes

### 2. Worker Node Preparation

On each worker node, run:

```bash
chmod +x k8s-worker-prerequisite.sh
sudo ./k8s-worker-prerequisite.sh
```

This creates the same `admin` user on worker nodes.

### 3. Deploy Your Cluster

Run the main interactive script on the master node:

```bash
chmod +x dynamic-all-rounder.sh
sudo ./dynamic-all-rounder.sh
```

## Menu Options

| Option | Description |
|--------|-------------|
| 1 | Install Kubernetes Cluster (with CNI selection) |
| 2 | Install Kubernetes Cluster with MetalLB LoadBalancer |
| 3 | Deploy MetalLB Service on existing cluster |
| 4 | Remove MetalLB Service from cluster |
| 5 | Remove entire Kubernetes cluster |
| 6 | Exit |

## Cluster Deployment Process

When you choose option 1 or 2, the script performs the following steps:

### Step 1-8: Container Runtime Setup
- Configure kernel modules (overlay, br_netfilter)
- Install Docker CE, CLI, and containerd
- Configure containerd with systemd cgroup
- Start and enable services

### Step 9-14: Kubernetes Installation
- Select Kubernetes version (auto-detects latest)
- Add Kubernetes apt repository
- Install kubelet, kubeadm, kubectl
- Disable swap permanently

### Step 15-18: Cluster Initialization
- Choose CNI plugin (Calico/Flannel/Weave Net)
- Initialize cluster with kubeadm
- Configure kubectl access
- Install selected CNI

### Step 19-21: Worker Node Provisioning
- Specify number of worker nodes
- Provide IP addresses for each worker
- Automatically copy join scripts and execute in parallel
- Verify cluster status

## Supported CNI Plugins

### Calico (Recommended)
- Feature-rich network policy support
- Default CIDR: Managed automatically
```yaml
# No additional CIDR configuration needed
```

### Flannel
- Simple overlay network
- Default CIDR: `10.244.0.0/16`
```yaml
# Automatically configured during init
```

### Weave Net
- Easy to deploy, encryption support
- Default CIDR: Managed automatically
```yaml
# No additional CIDR configuration needed
```

## MetalLB LoadBalancer

MetalLB provides LoadBalancer-type services for on-prem clusters lacking cloud provider support.

### IP Address Pool

During MetalLB setup, you'll need to specify an IP range:

```text
Enter your External IP Range: 192.168.1.100-192.168.1.200
```

**Important**: Ensure these IPs are:
- Available in your network
- Not assigned to any other device
- Accessible from your network

### Architecture

```
┌─────────────────────────────────────────────────┐
│                 Master Node                     │
│  ┌───────────────────────────────────────────┐  │
│  │   Kubernetes Control Plane                │  │
│  │   + API Server + Scheduler + Controller   │  │
│  └───────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────┐  │
│  │   MetalLB Controller                      │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
┌───────▼──────┐ ┌────▼─────┐ ┌────▼─────┐
│ Worker Node 1│ │Worker N 2│ │Worker N 3│
│  ┌─────────┐ │ │┌────────┐│ │┌────────┐│
│  │ Pod +   │ │ ││Pod +   ││ ││Pod +   ││
│  │ kubelet │ │ ││kubelet ││ ││kubelet ││
│  └─────────┘ │ │└────────┘│ │└────────┘│
└──────────────┘ └──────────┘ └──────────┘
```

## Removing the Cluster

To cleanly remove your Kubernetes cluster:

1. Run `dynamic-all-rounder.sh` and select option 5
2. Provide worker node IP addresses
3. The script will:
   - Execute `k8s-worker-remove.sh` on all worker nodes (in parallel)
   - Run `k8s-master-remove.sh` on master node
   - Clean up temporary files

## Individual Script Reference

### Main Scripts

| Script | Purpose |
|--------|---------|
| `dynamic-all-rounder.sh` | Main menu-driven cluster deployment tool |
| `k8s-master-prerequisite.sh` | Prepare master node with user and SSH setup |
| `k8s-worker-prerequisite.sh` | Prepare worker node with admin user |
| `k8s-worker-installation.sh` | Join worker to cluster (auto-executed) |
| `k8s-master-remove.sh` | Remove K8s from master node |
| `k8s-worker-remove.sh` | Remove K8s from worker node (auto-executed) |

## Verification Commands

After cluster deployment, verify with:

```bash
# Check node status
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Check MetalLB (if installed)
kubectl get pods -n metallb-system
kubectl get IPAddressPool -n metallb-system
kubectl get L2Advertisement -n metallb-system
```

## Troubleshooting

### Worker Node Not Ready
```bash
# Check kubelet logs
sudo journalctl -u kubelet -f

# Verify CNI pods are running
kubectl get pods -n kube-system
```

### MetalLB Not Assigning IPs
```bash
# Check MetalLB controller logs
kubectl logs -n metallb-system -l app=metallb-controller

# Verify IPAddressPool
kubectl describe IPAddressPool -n metallb-system
```

### SSH Connection Issues
```bash
# Test SSH connectivity
ssh admin@<worker-ip>

# Verify SSH keys
ls -la ~/.ssh/
```

## File Structure

```
.
├── dynamic-all-rounder.sh          # Main deployment script
├── k8s-master-prerequisite.sh      # Master node setup
├── k8s-worker-prerequisite.sh      # Worker node setup
├── k8s-worker-installation.sh      # Worker join script
├── k8s-master-remove.sh            # Master cleanup
├── k8s-worker-remove.sh            # Worker cleanup
├── Kubernates installtion.pdf      # Documentation (PDF)
└── Kubernates installtion.pptx     # Presentation (PPTX)
```

## Security Considerations

**Important Notes**:
- Default admin password (`ubuntu`) should be changed in production
- SSH key-based authentication is configured
- Sudoers are configured with NOPASSWD (modify for production)
- Consider using SSH bastion hosts for enhanced security

## Compatibility Matrix

| Component | Version |
|-----------|---------|
| Kubernetes | 1.24.x - 1.30.x (user selectable) |
| Containerd | Latest via Docker repo |
| Docker CE | Latest via Docker repo |
| Calico | v3.28.1 |
| Flannel | Master branch |
| Weave Net | v2.8.1 |
| MetalLB | v0.14.8 |
| Ubuntu | 20.04 LTS, 22.04 LTS |

## License

This project is provided as-is for educational and production use.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Author

Created by Bhavesh Panchal

## Support

For issues and questions, please open an issue on the GitHub repository.
