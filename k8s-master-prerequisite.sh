#!/bin/bash

# MAster node-prerequisite 

# install sshpass
sudo apt-get install sshpass

# Check if the script is run as root, if not, re-run the script with sudo
if [ "$EUID" -ne 0 ]; then
  echo "The script is not running as root. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

# Parameters
USER_NAME=admin
PASSWORD=ubuntu

# Check if username is provided
if [ -z "$USER_NAME" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

# Create a new user with the specified username and password
echo "Creating user '$USER_NAME'..."
useradd -m -s /bin/bash "$USER_NAME"
echo "$USER_NAME:$PASSWORD" | chpasswd
echo "User '$USER_NAME' created."

# Add the user to sudoers with NOPASSWD
echo "Adding '$USER_NAME' to sudoers with NOPASSWD..."
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
echo "'$USER_NAME' has been added to sudoers."

# Add the permission for the current user
sudo setfacl -R -m u:$(whoami):rwx /home/admin

# Add the default permission for the current user
sudo setfacl -R -m d:u:$(whoami):rwx /home/admin

# Generate SSH key
echo "Switching to user '$USER_NAME' and generating SSH key..."
sudo -u "$USER_NAME" bash -c "
  mkdir -p ~/.ssh
  ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa
  echo 'SSH key generated for $USER_NAME.'
"
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

# Copy SSH key to each worker node
for WORKER_IP in "${WORKER_IPS[@]}"; do
    echo "Copying SSH key to $USER_NAME@$WORKER_IP..."
    sshpass -p "$PASSWORD" sudo -u "$USER_NAME" ssh-copy-id -o StrictHostKeyChecking=no "$USER_NAME@$WORKER_IP"
done

echo "SSH keys have been copied to all worker nodes."

# # Ask for the number of worker nodes
# read -p "Enter the number of worker nodes: " WORKER_COUNT

# # Collect IP addresses of worker nodes
# WORKER_IPS=()
# for (( i=1; i<=WORKER_COUNT; i++ ))
# do
#     read -p "Enter the IP address of worker node $i: " WORKER_IP
#     WORKER_IPS+=("$WORKER_IP")
# done

# for WORKER_IP in "${WORKER_IPS[@]}"
# do
#     echo "Copying SSH key to $USER_NAME@$WORKER_IP..."
#     sshpass -p "$PASSWORD" sudo -u "$USER_NAME" ssh-copy-id -o StrictHostKeyChecking=no "$USER_NAME@$WORKER_IP"
# done

# Switch to user and change to their home directory
echo "Switching to user '$USER_NAME' and changing to their home directory..."
sudo -u "$USER_NAME" bash -c "cd ~ && exec bash"

# # Switch to user
# echo "Switching to user '$USER_NAME'..."
# sudo -u "$USER_NAME" bash

