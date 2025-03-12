## Minimum Requirements
* Ubuntu >=18 or Debian >=9
* CPU/Memory: 2 CPU/4GB RAM
* Storage: 100GB SSD hard drive
* DNS record A or Cloudflare Tunnel
* HTTP and HTTPS ports opened


## Run Nextcloud AIO
```bash
# Make sure to set NEXTCLOUD_DATADIR and NEXTCLOUD_MOUNT paths
docker compose -p homecloud up -d
# Reference: https://github.com/nextcloud/all-in-one?tab=readme-ov-file#nextcloud-all-in-one
```


## Encryption at rest
Only newly uploaded files will be encrypted, unless you run encrypt:all command
```bash
docker exec --user www-data -it nextcloud-aio-nextcloud php occ encryption:enable

docker exec --user www-data -it nextcloud-aio-nextcloud php occ encryption:status
# Reference: https://docs.nextcloud.com/server/latest/admin_manual/configuration_files/encryption_configuration.html#occ-encryption-commands
```

## Automatic backups and upload to S3 Glacier Deep Archive
First, enable automatic daily backups using AIO interface. Take note of the encryption password for backups.

Nextcloud uses BorgBackup as the underlying backup technology. By default, it sets a retention policy of:
- Keep 7 end of day, 4 additional end of week and 6 end of month archives

### Server configuration
1. Install required packages
```bash
sudo apt update && sudo apt install -y awscli jq

# Make sure to use the latest stable version of aws_signing_helper
wget https://rolesanywhere.amazonaws.com/releases/1.4.0/X86_64/Linux/aws_signing_helper
chmod +x aws_signing_helper
sudo mv aws_signing_helper /usr/local/bin/
```

2. Install rclone
```bash
sudo -v ; curl https://rclone.org/install.sh | sudo bash
```

3. Configure rclone, by changing settings in [rclone.conf file](rclone.conf). Then move it to your rclone config directory, usually `~/.config/rclone/rclone.conf`

4. Setup PKI for AWS login
```bash
# Create a private key for CA certificate
openssl genrsa -out homecloud-root-ca.key 4096

# Create CA certificate (valid for 10 years) using an OpenSSL configuration file
# Make sure to change all values inside the [ dn ] SECTION before applying the following command
openssl req -x509 -new -nodes -config certificates/selfsigned-ca.cnf -key homecloud-root-ca.key -days 3650 -out homecloud-root-ca.crt

# Create a private key for client certificate
openssl genrsa -out homecloud-client.key 2048

### Create client certificate Signing Request
# Make sure that the --subj argument values match the [ dn ] SECTION inside the selfsigned-ca.cnf configuration file before applying the following command
openssl req -new -key homecloud-client.key -out homecloud-client.csr -subj "/C=IT/ST=Ragusa/L=Acate/O=HomeCloud/CN=homecloud.yourdomain.com"

### Sign client certificate using CA (valid for 1 year) and use an OpenSSL configuration file
# to apply certificate extensions required by AWS
openssl x509 -req -in homecloud-client.csr -CA homecloud-root-ca.crt -CAkey homecloud-root-ca.key -CAcreateserial -out homecloud-client.crt -days 365 -sha256 -extfile certificates/homecloud-client.cnf -extensions homecloudclient_extensions
```


### AWS configuration
1. Create a Roles Anywhere Trust Anchor to estabilish trust between the server and AWS using the Certificate Authority:
- Certificate authority (CA) source = External certificate bundle
- External certificate bundle = Paste the content of homecloud-root-ca.crt into the box
- (Optional) customize Notification settings for certificates expiration alerts

2. Create an S3 bucket along with a Lifecycle rule with action "Expire current versions of objects" and set a value of your liking for "Days after object creation" field. This is for removing old tar.gz archives and free-up disk space

3. Create a [IAM Policy](iam/iam-role-policy.json) but change `s3bucketname` to match your S3 bucket name

4. Create a IAM Role:
- use Roles Anywhere as Service Principal
- attach the previously created permission policy to it
- add a [Trust Policy](iam/iam-role-trust-policy.json) but replace `rolesanywhere-trustanchor-arn` with the Trust Anchor ARN created before
- (Optional) customize Maximum session duration value according to your liking (currently 4hrs). Make sure to change the `--session-duration` parameter within [homecloud_backup.sh file](homecloud_backup.sh) accordingly.

5. Create a Roles Anywhere Profile:
- select the previously created IAM Role from the dropdown
- (Optional) customize Maximum session duration value according to your liking (currently 4hrs). Make sure to change the `--session-duration` parameter within [homecloud_backup.sh file](homecloud_backup.sh) accordingly.

### Backup configuration
1. Change the [ENV file](homecloud_backup.env) according to your setup then:
```bash
sudo mv homecloud_backup.env /etc/homecloud_backup.sh && sudo chmod 600 /etc/homecloud_backup.env

sudo mv homecloud_backup.sh /usr/local/bin/homecloud_backup.sh && sudo chmod 644 /usr/local/bin/homecloud_backup.sh
```

2. Set a Cronjob to automatically run the backup script
```bash
crontab -e
# Every 10 days at 4:00am
0 4 */10 * * bash /usr/local/bin/homecloud_backup.sh
```

## Restore files from S3 Deep Archive
```bash
# List S3 objects with StorageClass Glacier Deep Archive
aws s3api list-objects --bucket nextcloud-backups-personal-864430642600 | grep "StorageClass" | grep DEEP_ARCHIVE

# Change object StorageClass for 2 days from Deep Archive to Standard
aws s3api restore-object \
  --bucket nextcloud-backups-personal-864430642600 \
  --key "borg_2025-03-11_22-50-21.tar.gz" \
  --restore-request '{"Days":2, "GlacierJobParameters": {"Tier": "Standard"}}'

# Check restoration status
aws s3api head-object --bucket nextcloud-backups-personal-864430642600 --key borg_2025-03-11_22-50-21.tar.gz

# Misc
# check S3 bucket usage
aws s3 ls s3://nextcloud-backups-personal-864430642600 --recursive --human-readable --summarize
```

## Restore Nextcloud data into a new server
1.