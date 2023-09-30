## Requirements
* Ubuntu >=18 or Debian >=9
* CPU/Memory: 2 CPU/4GB RAM
* Storage: 100GB SSD hard drive
* DNS record A or Cloudflare Tunnel
* HTTP and HTTPS ports opened

## Installation
1. `sudo bash prereq.sh`

2. Open MySQL CLI to create your database and a dedicated user
`sudo mysql -u root -p`
```sql
CREATE DATABASE cells;
CREATE USER 'pydio'@'localhost' IDENTIFIED BY '<PUT YOUR PASSWORD HERE>';
GRANT ALL PRIVILEGES ON cells.* to 'pydio'@'localhost';
FLUSH PRIVILEGES;
```

3. Install with 
```bash
# As pydio user
sudo su - pydio 

# Download binary
wget -O /opt/pydio/bin/cells https://download.pydio.com/latest/cells/release/{latest}/linux-amd64/cells

# Make it executable
chmod a+x /opt/pydio/bin/cells

# Then as SYSADMIN user #################################
# Add permissions to bind to default HTTP ports
sudo setcap 'cap_net_bind_service=+ep' /opt/pydio/bin/cells

# Declare the cells commands system wide
sudo ln -s /opt/pydio/bin/cells /usr/local/bin/cells
```

## Configuration
1. 
```bash
sudo su - pydio 
cells configure
```
Then you can safely go for the browser install method. 

2. 
```bash
sudo su - pydio 
cells configure sites
```
Make sure to select:
- 8080 for Binding Port field
- 0.0.0.0 for Binding Host field
- Let's Encrypt for TLS section

    when asked, say Yes for Let's Encrypt staging entrypoint
- If using Cloudflare Tunnel or a reverse proxy, add your Cloudflare/reverse proxy FQDN for external URL field

[Example](sites-configuration.png)

3. Enable systemd service
```bash
sudo cp cells.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cells
sudo systemctl restart cells.service
```

## Storage configuration
TODO

## Alternatives (not tested yet)
- [Seafile](https://www.seafile.com/en/features/)
- [LinShare](https://www.linshare.org)
- [Aurora Files](https://afterlogic.org/aurora-files)
- [LinShare](https://www.linshare.org)