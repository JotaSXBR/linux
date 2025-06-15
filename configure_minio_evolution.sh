#!/bin/bash

# This script sets up the MinIO bucket and policy for Evolution API

# Get the Minio container ID
MINIO_CONTAINER=$(docker ps --filter name=minio_minio --format "{{.ID}}")

if [ -z "$MINIO_CONTAINER" ]; then
    echo "Error: MinIO container not found!"
    exit 1
fi

# MinIO client configuration through container exec
MC="docker exec $MINIO_CONTAINER mc"

# Replace these with your values
MINIO_ACCESS_KEY="root"
MINIO_SECRET_KEY="ae4b061ad9af723abf2aa0c91713d0fad9980af0432feefc0c75602087db6cb6"  # Your MinIO root password
EVOLUTION_USER="evolution"
EVOLUTION_PASS=$(openssl rand -hex 16)
BUCKET_NAME="evolution"

echo "Configuring MinIO client..."
$MC alias set local http://localhost:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

echo "Creating Evolution API user..."
$MC admin user add local $EVOLUTION_USER $EVOLUTION_PASS

echo "Creating bucket (if it doesn't exist)..."
$MC mb local/$BUCKET_NAME 2>/dev/null || true

echo "Creating policy in container..."
# Create the policy file in the container
docker exec $MINIO_CONTAINER sh -c 'cat > /tmp/evolution-policy.json' << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::evolution/*",
                "arn:aws:s3:::evolution"
            ]
        }
    ]
}
EOF

echo "Creating policy..."
$MC admin policy create local evolution-policy /tmp/evolution-policy.json

echo "Applying policy to user..."
$MC admin policy attach local evolution-policy --user $EVOLUTION_USER

echo "Setting bucket policy to download..."
$MC anonymous set download local/$BUCKET_NAME

echo "Configuration complete!"
echo "Use these credentials in Evolution API setup:"
echo "Access Key: $EVOLUTION_USER"
echo "Secret Key: $EVOLUTION_PASS"
echo
echo "Test the configuration:"
echo "Try creating a test file:"
echo 'echo "test" | '$MC' pipe local/'$BUCKET_NAME'/test.txt'
