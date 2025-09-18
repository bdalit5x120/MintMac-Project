#! /bin/bash
# Create new hosts

echo "Creating new host keys for SSH"
sudo ssh-keygen -A

echo "restarting the server"
sudo systemctl enable ssh
sudo systemctl restart ssh

echo "Done"
