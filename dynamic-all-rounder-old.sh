#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Print each command before executing it
#set -x

# Greeting
echo "Hello, User!"

# Menu Options
echo "Please choose an option:"
echo "1) Install kubernetes Cluster"
echo "2) Install Kubernetes Cluster with MetalLB"
echo "3) Remove  Kubernetes Cluster"

read -p "Enter your choice (1,2 or 3): " CHOICE

# Conditional execution based on user input
if [ "$CHOICE" -eq 1 ]; then
    echo "You chose to install the Kubernetes cluster."

    # Step 1: Configure persistent loading of modules
    sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

    # Step 2: Install Docker
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo docker --version
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
    sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg

    # Install jq
    sudo snap install jq


    # Function to get Kubernetes versions
    get_k8s_versions() {
        curl -s https://api.github.com/repos/kubernetes/kubernetes/releases | jq -r '.[].tag_name' | sed 's/^v//' | sort -V
    }

    # Get available Kubernetes versions and the latest version
    AVAILABLE_VERSIONS=$(get_k8s_versions)
    LATEST_VERSION=$(echo "$AVAILABLE_VERSIONS" | tail -n 1)

    # Check if versions are fetched
    if [[ -z "$AVAILABLE_VERSIONS" ]]; then
        echo "Failed to fetch Kubernetes versions. Please check your internet connection or the URL."
        exit 1
    fi

    # Loop until a valid version is selected
    while true; do
        # Prompt user to select a Kubernetes version
        echo "Available Kubernetes versions:"
        echo "$AVAILABLE_VERSIONS"
        echo ""
        echo "The latest Kubernetes version is: $LATEST_VERSION"
        echo ""

        # Suggest the latest version to the user
        read -p "Enter the version you want to install (or press Enter to select the latest version $LATEST_VERSION): " K8S_VERSION

        # Default to the latest version if none is provided
        if [[ -z "$K8S_VERSION" ]]; then
        K8S_VERSION="$LATEST_VERSION"
        echo "No version selected. Using the latest version: $LATEST_VERSION"
        fi

        # Ensure user input is valid
        if [[ "$AVAILABLE_VERSIONS" =~ (^|[[:space:]])"$K8S_VERSION"($|[[:space:]]) ]]; then
            echo "Selected Kubernetes version: $K8S_VERSION"
            break
        else
            echo "Invalid version selected. Please choose a valid version from the list."
        fi
    done

    # Adjust version format to two-digit for URL
    VERSION_FORMATTED=$(echo "$K8S_VERSION" | sed 's/^\([0-9]*\.[0-9]*\).*$/\1/')

    # Add the Kubernetes repository to the system’s package sources
    echo "Selected Kubernetes version: $K8S_VERSION"

    # Save the selected version to a file
    echo "$K8S_VERSION" > /home/admin/selected_k8s_version.txt  # Specify the appropriate path

    # Step 7: Add the Kubernetes repository to the system’s package sources
    sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg
    sudo curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${VERSION_FORMATTED}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${VERSION_FORMATTED}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list


    # Step 11: Install kubelet, kubeadm, and kubectl packages
    sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl

    # Step 12: Hold the installed packages at their current versions
    sudo apt-mark hold kubelet kubeadm kubectl
    
    # Step 13: Enable the kubelet service on all nodes
    sudo systemctl enable --now kubelet

    # Step 14: Permanently disable swap
    sudo swapoff -a
    sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    sudo free -h

    # Step 15: Choose Kubernetes CNI
    echo "Choose the Network CNI to install:"
    echo "1. Calico"
    echo "2. Flannel"
    echo "3. Weave Net"
    read -p "Enter the number of the CNI you want to install: " CNI_CHOICE

    # Step 16: Setup kubeadm based on CNI choice
    if [ "$CNI_CHOICE" -eq 1 ]; then
        sudo kubeadm init | tee /dev/tty | grep -A1 "kubeadm join" > kubeadm-join.txt
    elif [ "$CNI_CHOICE" -eq 2 ]; then
        sudo kubeadm init --pod-network-cidr=10.244.0.0/16 | tee /dev/tty | grep -A1 "kubeadm join" > kubeadm-join.txt
    elif [ "$CNI_CHOICE" -eq 3 ]; then
        sudo kubeadm init | tee /dev/tty | grep -A1 "kubeadm join" > kubeadm-join.txt
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi

    # Step 17: Add configuration for kubeadm and set KUBECONFIG for all users
    echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' | sudo tee -a /etc/profile
    echo 'KUBECONFIG="/etc/kubernetes/admin.conf"' | sudo tee -a /etc/environment
    echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' | sudo tee -a /etc/bash.bashrc
    source /etc/profile
    source /etc/environment
    source /etc/bash.bashrc
    sudo mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Step 18: Install the selected CNI
    if [ "$CNI_CHOICE" -eq 1 ]; then
        echo "Installing Calico CNI..."
        sudo kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/calico.yaml
    elif [ "$CNI_CHOICE" -eq 2 ]; then
        echo "Installing Flannel CNI with specific pod network CIDR..."
        sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    elif [ "$CNI_CHOICE" -eq 3 ]; then
        echo "Installing Weave Net CNI..."
        sudo kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
    fi

    # Step 19: Check nodes
    sudo kubectl get nodes -o wide

    # Step 20: Define the list of worker nodes and the network details

    # Ask for the number of worker nodes
    while true; do
        read -p "Enter the number of worker nodes (must be between 0 and 100): " WORKER_COUNT
        # Validate WORKER_COUNT to ensure it's a number between 0 and 100 (inclusive)
        if [[ "$WORKER_COUNT" =~ ^[0-9]$|^[1-9][0-9]$|^100$ ]]; then
            break
        else
            echo "Invalid input. Please enter a number between 0 and 100."
        fi
    done

    # Function to validate IP addresses
    validate_ip() {
        local ip=$1
        local stat=1
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            OIFS=$IFS
            IFS='.'
            ip=($ip)
            IFS=$OIFS
            [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
            stat=$?
        fi
        return $stat
    }

    # Collect IP addresses of worker nodes
    WORKER_IPS=()
    for (( i=1; i<=WORKER_COUNT; i++ )); do
        while true; do
            read -p "Enter the IP address of worker node $i: " WORKER_IP
            # Validate the IP address
            if validate_ip "$WORKER_IP"; then
                WORKER_IPS+=("$WORKER_IP")
                break
            else
                echo "Invalid IP address. Please try again."
            fi
        done
    done

    # Define other variables
    USERNAME="admin"  # Replace with the appropriate username if different on each node
    SOURCE_FILES=("kubeadm-join.txt" "k8s-worker-installation.sh" "k8s-worker-remove.sh" "selected_k8s_version.txt" )  # Add more files as needed
    DESTINATION_PATH="/home/admin/"

    # Iterate over each worker node
    for IP in "${WORKER_IPS[@]}"; do
        (
        echo "Copying files to $USERNAME@$IP:$DESTINATION_PATH"
        
        # Iterate over each source file
        for FILE in "${SOURCE_FILES[@]}"; do
            echo "Copying $FILE to $USERNAME@$IP:$DESTINATION_PATH"
            scp "$FILE" "$USERNAME@$IP:$DESTINATION_PATH" &
        done
        
        # Wait for all file copies to complete
        wait

        # Run the k8s-worker-installation.sh script on the worker node
        echo "Running k8s-worker-installation.sh on $USERNAME@$IP"
        ssh "$USERNAME@$IP" "chmod +x $DESTINATION_PATH/k8s-worker-installation.sh && $DESTINATION_PATH/k8s-worker-installation.sh"
        ) &
    done
    
    # Wait for all background processes to complete
    wait

    echo "All files have been copied to all worker nodes successfully."

    # Step 21: check pods
    if [ "$CNI_CHOICE" -eq 1 ] || [ "$CNI_CHOICE" -eq 3 ]; then
        sudo kubectl get pods -n kube-system -o wide
    elif [ "$CNI_CHOICE" -eq 2 ]; then
        sudo kubectl get pods -n kube-flannel -o wide
    fi

# Conditional execution based on user input
elif [ "$CHOICE" -eq 2 ]; then
    echo "You chose to install the Kubernetes cluster with  MetalLB."

    # Step 1: Configure persistent loading of modules
    sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

    # Step 2: Install Docker
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo docker --version
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
    sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg

    # Install jq
    sudo snap install jq


    # Function to get Kubernetes versions
    get_k8s_versions() {
        curl -s https://api.github.com/repos/kubernetes/kubernetes/releases | jq -r '.[].tag_name' | sed 's/^v//' | sort -V
    }

    # Get available Kubernetes versions and the latest version
    AVAILABLE_VERSIONS=$(get_k8s_versions)
    LATEST_VERSION=$(echo "$AVAILABLE_VERSIONS" | tail -n 1)

    # Check if versions are fetched
    if [[ -z "$AVAILABLE_VERSIONS" ]]; then
        echo "Failed to fetch Kubernetes versions. Please check your internet connection or the URL."
        exit 1
    fi

    # Loop until a valid version is selected
    while true; do
        # Prompt user to select a Kubernetes version
        echo "Available Kubernetes versions:"
        echo "$AVAILABLE_VERSIONS"
        echo ""
        echo "The latest Kubernetes version is: $LATEST_VERSION"
        echo ""

        # Suggest the latest version to the user
        read -p "Enter the version you want to install (or press Enter to select the latest version $LATEST_VERSION): " K8S_VERSION

        # Default to the latest version if none is provided
        if [[ -z "$K8S_VERSION" ]]; then
        K8S_VERSION="$LATEST_VERSION"
        echo "No version selected. Using the latest version: $LATEST_VERSION"
        fi

        # Ensure user input is valid
        if [[ "$AVAILABLE_VERSIONS" =~ (^|[[:space:]])"$K8S_VERSION"($|[[:space:]]) ]]; then
            echo "Selected Kubernetes version: $K8S_VERSION"
            break
        else
            echo "Invalid version selected. Please choose a valid version from the list."
        fi
    done

    # Adjust version format to two-digit for URL
    VERSION_FORMATTED=$(echo "$K8S_VERSION" | sed 's/^\([0-9]*\.[0-9]*\).*$/\1/')

    # Add the Kubernetes repository to the system’s package sources
    echo "Selected Kubernetes version: $K8S_VERSION"

    # Save the selected version to a file
    echo "$K8S_VERSION" > /home/admin/selected_k8s_version.txt  # Specify the appropriate path

    # Step 7: Add the Kubernetes repository to the system’s package sources
    sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg
    sudo curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${VERSION_FORMATTED}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${VERSION_FORMATTED}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list


    # Step 11: Install kubelet, kubeadm, and kubectl packages
    sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl

    # Step 12: Hold the installed packages at their current versions
    sudo apt-mark hold kubelet kubeadm kubectl

    # Step 13: Enable the kubelet service on all nodes
    sudo systemctl enable --now kubelet

    # Step 14: Permanently disable swap
    sudo swapoff -a
    sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    sudo free -h

    # Step 15: Choose Kubernetes CNI
    echo "Choose the Network CNI to install:"
    echo "1. Calico"
    echo "2. Flannel"
    echo "3. Weave Net"
    read -p "Enter the number of the CNI you want to install: " CNI_CHOICE

    # Step 16: Setup kubeadm based on CNI choice
    if [ "$CNI_CHOICE" -eq 1 ]; then
        sudo kubeadm init | tee /dev/tty | grep -A1 "kubeadm join" > kubeadm-join.txt
    elif [ "$CNI_CHOICE" -eq 2 ]; then
        sudo kubeadm init --pod-network-cidr=10.244.0.0/16 | tee /dev/tty | grep -A1 "kubeadm join" > kubeadm-join.txt
    elif [ "$CNI_CHOICE" -eq 3 ]; then
        sudo kubeadm init | tee /dev/tty | grep -A1 "kubeadm join" > kubeadm-join.txt
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi

    # Step 17: Add configuration for kubeadm and set KUBECONFIG for all users
    echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' | sudo tee -a /etc/profile
    echo 'KUBECONFIG="/etc/kubernetes/admin.conf"' | sudo tee -a /etc/environment
    echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' | sudo tee -a /etc/bash.bashrc
    source /etc/profile
    source /etc/environment
    source /etc/bash.bashrc
    sudo mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Step 18: Install the selected CNI
    if [ "$CNI_CHOICE" -eq 1 ]; then
        echo "Installing Calico CNI..."
        sudo kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/calico.yaml
    elif [ "$CNI_CHOICE" -eq 2 ]; then
        echo "Installing Flannel CNI with specific pod network CIDR..."
        sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    elif [ "$CNI_CHOICE" -eq 3 ]; then
        echo "Installing Weave Net CNI..."
        sudo kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
    fi

    # Step 19: Check nodes
    sudo kubectl get nodes -o wide

    # Step 20: Define the list of worker nodes and the network details

    # Ask for the number of worker nodes
    while true; do
        read -p "Enter the number of worker nodes (must be between 0 and 100): " WORKER_COUNT
        # Validate WORKER_COUNT to ensure it's a number between 0 and 100 (inclusive)
        if [[ "$WORKER_COUNT" =~ ^[0-9]$|^[1-9][0-9]$|^100$ ]]; then
            break
        else
            echo "Invalid input. Please enter a number between 0 and 100."
        fi
    done
    
    # Function to validate IP addresses
    validate_ip() {
        local ip=$1
        local stat=1
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            OIFS=$IFS
            IFS='.'
            ip=($ip)
            IFS=$OIFS
            [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
            stat=$?
        fi
        return $stat
    }
    # Collect IP addresses of worker nodes
    WORKER_IPS=()
    for (( i=1; i<=WORKER_COUNT; i++ )); do
        while true; do
            read -p "Enter the IP address of worker node $i: " WORKER_IP
            # Validate the IP address
            if validate_ip "$WORKER_IP"; then
                WORKER_IPS+=("$WORKER_IP")
                break
            else
                echo "Invalid IP address. Please try again."
            fi
        done
    done

    # Define other variables
    USERNAME="admin"  # Replace with the appropriate username if different on each node
    SOURCE_FILES=("kubeadm-join.txt" "k8s-worker-installation.sh" "k8s-worker-remove.sh" "selected_k8s_version.txt")  # Add more files as needed
    DESTINATION_PATH="/home/admin/"

    # Iterate over each worker node
    for IP in "${WORKER_IPS[@]}"; do
        (
        echo "Copying files to $USERNAME@$IP:$DESTINATION_PATH"
        
        # Iterate over each source file
        for FILE in "${SOURCE_FILES[@]}"; do
            echo "Copying $FILE to $USERNAME@$IP:$DESTINATION_PATH"
            scp "$FILE" "$USERNAME@$IP:$DESTINATION_PATH" &
        done

        # Wait for all file copies to complete
        wait

        # Run the k8s-worker-installation.sh script on the worker node
        echo "Running k8s-worker-installation.sh on $USERNAME@$IP"
        ssh "$USERNAME@$IP" "chmod +x $DESTINATION_PATH/k8s-worker-installation.sh && $DESTINATION_PATH/k8s-worker-installation.sh"
        ) &
    done

    echo "All files have been copied to all worker nodes successfully."

    # Wait for all background processes to complete
    wait

    # Step 21: Install MetalLB

    # Step 1: Modify the strictARP parameter
    sudo kubectl get configmap kube-proxy -n kube-system -o yaml | \
      sed 's/strictARP: false/strictARP: true/' | \
      sudo kubectl apply -f -

    echo "kube-proxy ConfigMap has been updated: strictARP is now set to true."

    # Step 2: Install the MetalLB load balancer using the manifest file
    sudo kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

    # Step 3: Check the MetalLB deployment
    sudo kubectl get all -n metallb-system

    # Step 4: Check the MetalLB custom resources
    sudo kubectl api-resources | grep metallb

    # Step 5: Check the MetalLB pods
    sudo kubectl get pods -n metallb-system

    # Function to validate IP addresses
    validate_ip() {
        local ip=$1
        local stat=1
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            OIFS=$IFS
            IFS='.'
            ip=($ip)
            IFS=$OIFS
            [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
            stat=$?
        fi
        return $stat
    }   

    # Step 6: Creation of MetalLB IPAddressPool file
    while true; do
        read -p "Enter your External IP Range for Load-balancer service type (e.g., 192.168.0.0-192.168.0.255): " EXTERNAL_IP_RANGE

        # Validate the IP range input format
        if [[ $EXTERNAL_IP_RANGE =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # Split the range into start and end IPs
            IFS='-' read -r START_IP END_IP <<< "$EXTERNAL_IP_RANGE"

            # Validate both the start and end IPs
            if validate_ip "$START_IP" && validate_ip "$END_IP"; then
                echo "Valid IP range entered: $EXTERNAL_IP_RANGE"
                break
            else
                echo "Invalid IP address in the range. Please try again."
            fi
        else
            echo "Invalid IP range format. Please enter a valid IP range in the format x.x.x.x-x.x.x.x."
        fi
    done
    
    # Create the YAML file using a here-document
    sudo cat <<EOF > IPAddressPool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: cheap
  namespace: metallb-system
spec:
  addresses:
  - $EXTERNAL_IP_RANGE
EOF
    # step-6 add slip time
   sudo sleep 90

    # step-7  apply IPAddressPool file
    sudo kubectl apply -f IPAddressPool.yaml
 
    # check ip address pool deployed on metal-lb
    sudo kubectl get IPAddressPool -n metallb-system
 
    # step-8 creation of  l2advertisement resource
 
    # Create the YAML file for the L2Advertisement resource using a here-document
    sudo cat <<EOF > l2advertisement.yaml
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: on-prem-cluster
      namespace: metallb-system
    spec:
      ipAddressPools:
      - cheap
EOF

    #  step-9 apply l2advertisement file
    sudo kubectl apply -f l2advertisement.yaml
 
    # step-10 check l2advertisement deployed on metal-lb
    sudo kubectl get l2advertisement -n metallb-system


    # Step 22: check pods
    if [ "$CNI_CHOICE" -eq 1 ] || [ "$CNI_CHOICE" -eq 3 ]; then
        sudo kubectl get pods -n kube-system -o wide
    elif [ "$CNI_CHOICE" -eq 2 ]; then
        sudo kubectl get pods -n kube-flannel -o wide
    fi


elif [ "$CHOICE" -eq 3 ]; then
    echo "You chose to remove the Kubernetes cluster."
    
    # task-1 worker-nodes removal task

    # Ask for the number of worker nodes
    while true; do
        read -p "Enter the number of worker nodes (must be between 0 and 100): " WORKER_COUNT
        # Validate WORKER_COUNT to ensure it's a number between 0 and 100 (inclusive)
        if [[ "$WORKER_COUNT" =~ ^[0-9]$|^[1-9][0-9]$|^100$ ]]; then
            break
        else
            echo "Invalid input. Please enter a number between 0 and 100."
        fi
    done

    # Function to validate IP addresses
    validate_ip() {
        local ip=$1
        local stat=1
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            OIFS=$IFS
            IFS='.'
            ip=($ip)
            IFS=$OIFS
            [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
            stat=$?
        fi
        return $stat
    }

    # Collect IP addresses of worker nodes
    WORKER_IPS=()
    for (( i=1; i<=WORKER_COUNT; i++ )); do
        while true; do
            read -p "Enter the IP address of worker node $i: " WORKER_IP
            # Validate the IP address
            if validate_ip "$WORKER_IP"; then
                WORKER_IPS+=("$WORKER_IP")
                break
            else
                echo "Invalid IP address. Please try again."
            fi
        done
    done

    # Define other variables
    USERNAME="admin"  # Replace with the appropriate username if different on each node
    SOURCE_FILES=("kubeadm-join.txt" "k8s-worker-installation.sh" "k8s-worker-remove.sh" "selected_k8s_version.txt")  # Add more files as needed
    DESTINATION_PATH="/home/admin/"

    # Iterate over each worker node
    for IP in "${WORKER_IPS[@]}"; do
        (
        # Run the k8s-worker-remove.sh  script on the both worker node
        echo "Running k8s-worker-remove.sh on $USERNAME@$IP"
        ssh "$USERNAME@$IP" "chmod +x $DESTINATION_PATH/k8s-worker-remove.sh && $DESTINATION_PATH/k8s-worker-remove.sh"
        
        # Wait for all file copies to complete
        wait

        # Removed copied files from worker nodes
        echo "Removing copied files from worker nodes on $USERNAME@$IP"
        ssh "$USERNAME@$IP" "rm -rf $DESTINATION_PATH/k8s-worker-installation.sh k8s-worker-remove.sh kubeadm-join.txt selected_k8s_version.txt"
        ) &
    done

    # Wait for all background processes to complete
    wait

    echo "All worker nodes are removed successfully."

    # task-2 Master nodes removal task
    ./k8s-master-remove.sh

    # task-3 Removed copied files from Master nodes 
    sudo rm -rf IPAddressPool.yaml k8s-master-remove.sh k8s-worker-remove.sh l2advertisement.yaml k8s-worker-installation.sh kubeadm-join.txt dynamic-all-rounder.sh selected_k8s_version.txt

    echo "Kubernetes cluster has been removed."
else
    echo "Invalid choice. Please run the script again and choose either 1,2 or 3."
    exit 1
fi