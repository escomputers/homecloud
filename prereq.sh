# Create pydio user with a home directory
sudo useradd -m -s /bin/bash pydio

# Create necessary folders
sudo mkdir -p /opt/pydio/bin /var/cells
sudo chown -R pydio: /opt/pydio /var/cells

# Add system-wide ENV var
sudo tee -a /etc/profile.d/cells-env.sh << EOF
export CELLS_WORKING_DIR=/var/cells
EOF
sudo chmod 0755 /etc/profile.d/cells-env.sh

# Install the server from the default repository
sudo apt install mariadb-server -y
# Run the script to secure your install
sudo mysql_secure_installation