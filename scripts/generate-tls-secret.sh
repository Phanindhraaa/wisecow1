#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# generate-tls-secret.sh
# Generates a self-signed TLS certificate and creates a Kubernetes secret.
# For production use cert-manager or a real CA instead.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOMAIN="${1:-wisecow.example.com}"
NAMESPACE="wisecow"
SECRET_NAME="wisecow-tls"
TLS_DIR="./tls"

echo "[INFO] Generating TLS cert for domain: $DOMAIN"
mkdir -p "$TLS_DIR"

# Generate private key
openssl genrsa -out "$TLS_DIR/tls.key" 2048

# Generate self-signed certificate (valid 365 days)
openssl req -new -x509 \
    -key "$TLS_DIR/tls.key" \
    -out "$TLS_DIR/tls.crt" \
    -days 365 \
    -subj "/CN=$DOMAIN/O=WiseCow/C=IN" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost"

echo "[INFO] Certificate generated:"
openssl x509 -in "$TLS_DIR/tls.crt" -text -noout | grep -E "Subject:|DNS:"

# Create / update the Kubernetes secret
echo "[INFO] Creating Kubernetes TLS secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls "$SECRET_NAME" \
    --cert="$TLS_DIR/tls.crt" \
    --key="$TLS_DIR/tls.key" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "[SUCCESS] TLS secret '$SECRET_NAME' is ready."
