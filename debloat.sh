#!/bin/bash

# Print a message to indicate the script is starting
echo "Starting debloat and cleanup process..."

# Update the package list
echo "Updating package list..."
sudo apt update -y

# Remove unused packages and dependencies
echo "Removing unused packages and dependencies..."
sudo apt autoremove -y
sudo apt-get autoremove --purge -y

# Clean up the local repository of retrieved package files
echo "Cleaning up local package cache..."
sudo apt-get clean

# Remove old kernels (keeping the current one)
echo "Removing old kernels..."
current_kernel=$(uname -r)
sudo dpkg --list | grep linux-image | grep -v "$current_kernel" | awk '{ print $2 }' | sudo xargs apt-get -y purge

# Install deborphan to find orphaned packages (optional)
echo "Installing deborphan to clean orphaned packages..."
sudo apt install deborphan -y

# Remove orphaned packages
echo "Removing orphaned packages..."
sudo apt-get remove --purge -y $(deborphan)

# Remove Snap if not required
echo "Removing Snap packages..."
sudo apt purge snapd -y

# Remove pre-installed apps (you can modify the list as needed)
echo "Removing pre-installed applications..."
sudo apt remove --purge -y gnome-games gnome-software
# Add more packages to remove as needed
# sudo apt remove --purge -y PACKAGE_NAME

# Clean up log files older than 7 days
echo "Cleaning up old system logs..."
sudo journalctl --vacuum-time=7d

# Clean up apt cache (optional)
echo "Cleaning apt cache..."
sudo apt-get autoremove -y && sudo apt-get clean

# Check and disable unnecessary services (example: bluetooth if not needed)
echo "Disabling unnecessary services..."
sudo systemctl disable bluetooth

# Final message
echo "Debloating and cleanup complete."
