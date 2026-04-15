#!/bin/bash
# Initialize Docker Secrets for Production Deployment
# Run this script to generate and store secure secrets

set -e

SECRETS_DIR="./secrets"
echo "=== POS System Secrets Initialization ==="
echo ""

# Create secrets directory
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Generate cryptographically secure secrets
echo "Generating cryptographically secure secrets..."

# JWT Secret (64 bytes base64)
if [ ! -f "$SECRETS_DIR/jwt_secret" ]; then
    openssl rand -base64 64 > "$SECRETS_DIR/jwt_secret"
    echo "✓ Generated JWT_SECRET"
else
    echo "⚠ JWT_SECRET already exists, skipping..."
fi

# JWT Refresh Secret (64 bytes base64)
if [ ! -f "$SECRETS_DIR/jwt_refresh_secret" ]; then
    openssl rand -base64 64 > "$SECRETS_DIR/jwt_refresh_secret"
    echo "✓ Generated JWT_REFRESH_SECRET"
else
    echo "⚠ JWT_REFRESH_SECRET already exists, skipping..."
fi

# Database Password (32 chars alphanumeric + symbols)
if [ ! -f "$SECRETS_DIR/database_password" ]; then
    openssl rand -base64 32 | tr -dc 'A-Za-z0-9!@#$%^&*' | head -c 32 > "$SECRETS_DIR/database_password"
    echo "" >> "$SECRETS_DIR/database_password"  # Add newline
    echo "✓ Generated DATABASE_PASSWORD"
else
    echo "⚠ DATABASE_PASSWORD already exists, skipping..."
fi

# Redis Password (32 chars)
if [ ! -f "$SECRETS_DIR/redis_password" ]; then
    openssl rand -base64 32 | tr -dc 'A-Za-z0-9!@#$%^&*' | head -c 32 > "$SECRETS_DIR/redis_password"
    echo "" >> "$SECRETS_DIR/redis_password"  # Add newline
    echo "✓ Generated REDIS_PASSWORD"
else
    echo "⚠ REDIS_PASSWORD already exists, skipping..."
fi

# Payment provider secrets (placeholders - must be filled manually)
for secret in daraja_consumer_key daraja_consumer_secret daraja_passkey pesapal_consumer_key pesapal_consumer_secret touristtap_api_key; do
    if [ ! -f "$SECRETS_DIR/$secret" ]; then
        echo "PLACEHOLDER_${secret^^}_GET_FROM_PROVIDER" > "$SECRETS_DIR/$secret"
        echo "⚠ Created placeholder for $secret - UPDATE WITH REAL VALUE"
    else
        echo "✓ $secret exists"
    fi
done

# Set restrictive permissions
chmod 600 "$SECRETS_DIR"/*
echo ""
echo "=== Secrets Directory Permissions ==="
ls -la "$SECRETS_DIR"

echo ""
echo "=== Security Notes ==="
echo "1. NEVER commit the ./secrets directory to git"
echo "2. Update payment provider placeholders with real credentials"
echo "3. Rotate secrets every 90 days minimum"
echo "4. For production, use a secrets manager (Vault, AWS Secrets Manager, etc.)"
echo "5. Backup secrets securely offline"
echo ""
echo "=== Next Steps ==="
echo "1. Update payment provider credentials in $SECRETS_DIR/"
echo "2. Run: docker stack deploy -c docker-compose.prod.yml pos"
echo ""
