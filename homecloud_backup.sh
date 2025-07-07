#!/usr/bin/env bash

# Load .env file
source /etc/homecloud_backup.env

# Constants
HOSTNAME=$(hostname)
LOG_FILE="/var/log/homecloud_backup.log"
FILENAME=borg_$(date +'%Y-%m-%d_%H-%M-%S').tar.gz
FILEPATH="$BACKUP_DIR"/"$FILENAME"

# Define retry parameters
MAX_RETRIES=3
DELAY=10 # initial delay in seconds

# Init log file
exec >> "$LOG_FILE" 2>&1

# Email sender function
send_email() {
    local subject="$1"
    local body="$2"

    # Construct the email message
    message="Subject: $subject\n\n$body"

    curl --url "$ALERTMAIL_CONN_STRING" \
        --ssl-reqd \
        --mail-from "$ALERTMAIL_SENDER" \
        --mail-rcpt "$ALERTMAIL_RECIPIENT" \
        --user "$ALERTMAIL_SENDER:$ALERTMAIL_GMAIL_APP_PWD" \
        -T <(echo -e "$message")
}

# Create an tar archive of Borg repository
tar -czvf "$FILEPATH" "$BACKUP_DIR"/borg
echo "Created tar archive: $FILEPATH"

# Get credentials and save them in a file
aws_signing_helper credential-process \
    --certificate "$AWS_CERTIFICATE_PATH" \
    --private-key "$AWS_PRIVATE_KEY_PATH" \
    --trust-anchor-arn "$AWS_TRUST_ANCHOR_ARN" \
    --profile-arn "$AWS_ROLE_PROFILE_ARN" \
    --session-duration 14400 \
    --role-arn "$AWS_ROLE_ARN" >"$CREDENTIALS_PATH"

# Extract credentials from the file
AWS_ACCESS_KEY_ID="$(jq -r ".AccessKeyId" "$CREDENTIALS_PATH")"
export AWS_ACCESS_KEY_ID

AWS_SECRET_ACCESS_KEY="$(jq -r ".SecretAccessKey" "$CREDENTIALS_PATH")"
export AWS_SECRET_ACCESS_KEY

AWS_SESSION_TOKEN="$(jq -r ".SessionToken" "$CREDENTIALS_PATH")"
export AWS_SESSION_TOKEN

echo "Fetched AWS credentials"

sleep 3

# Copy the archive to the S3 bucket with retry mechanism
for ((attempt = 1; attempt <= MAX_RETRIES; attempt++)); do
    echo "Attempt $attempt: Uploading $FILENAME to $BACKUP_BUCKET"
	echo "[rclone] Starting upload"
    if rclone copyto --log-level INFO "$FILEPATH" s3-bucket:"$BACKUP_BUCKET/$FILENAME"; then
		echo "[rclone] Upload completed"
        echo "Upload successful on attempt $attempt"
        break
    else
        echo "Upload failed on attempt $attempt"
        if ((attempt < MAX_RETRIES)); then
            echo "Retrying in $DELAY seconds"
            sleep $DELAY
            DELAY=$((DELAY * 2)) # Exponential retry
        else
            rm -f "$FILEPATH"
            echo "Upload failed after $MAX_RETRIES attempts. Deleted local archive $FILEPATH"

            # Send alert email after all failed attempts
            error_subject="$HOSTNAME: WARNING! FAILED upload of Borg repo archive to S3 bucket"
            error_body="Check $LOG_FILE for issues."

            if send_email "$error_subject" "$error_body"; then
                echo "Alert email sent"
            else
                echo "Cannot send email"
            fi

            exit 1
        fi
    fi
done

# Get archive size
backup_size=$(du -sh "$FILEPATH")

# Remove the transferred archive from the local filesystem
rm -f "$FILEPATH"

# Send email also on success
success_subject="$HOSTNAME: Successfully uploaded Borg repo archive to S3 bucket"
success_body="$backup_size, successfully uploaded to $BACKUP_BUCKET bucket"

if send_email "$success_subject" "$success_body"; then
    echo "Backup process completed successfully. $FILEPATH deleted. Email sent!"
else
    echo "Cannot send email but backup completed successfully"
fi
