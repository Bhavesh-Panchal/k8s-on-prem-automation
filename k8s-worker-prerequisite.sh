#!/bin/bash

# workernode-prerequisite 

# Check if the script is run as root, if not, re-run the script with sudo
if [ "$EUID" -ne 0 ]; then
  echo "The script is not running as root. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

# Parameters
USER_NAME=admin
PASSWORD=ubuntu

# Check if username and password are provided
if [ -z "$USER_NAME" ] || [ -z "$PASSWORD" ]; then
  echo "Usage: $0 <username> <password>"
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

# # Add the permission for the current user
# sudo setfacl -R -m u:$(whoami):rwx /home/admin

# # Add the default permission for the current user
# sudo setfacl -R -m d:u:$(whoami):rwx /home/admin

# Switch to user and change to their home directory
echo "Switching to user '$USER_NAME' and changing to their home directory..."
sudo -u "$USER_NAME" bash -c "cd ~ && exec bash"

# # Switch to root user, change to the new user's home directory, and start a new shell session there
# echo "Switching to root user and changing to /home/$USER_NAME..."
# sudo -i bash -c "cd /home/$USER_NAME && exec bash"

# # Confirm the actions
# echo "User '$USER_NAME' has been granted sudo privileges without a password."
# echo "Now in /home/$USER_NAME as root user."


