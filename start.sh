#!/bin/sh
set -e

echo "=== Starting OpenClaw with Tailscale support ==="

# Default values - non-root compatible paths
TS_SOCKS_PORT=${TS_SOCKS_PORT:-1055}
TS_HOSTNAME=${TS_HOSTNAME:-openclaw-render}
VPS_TAILSCALE_IP=${VPS_TAILSCALE_IP:-100.82.227.84}
VPS_SSH_USER=${VPS_SSH_USER:-root}
# IMPORTANT: Replace OPENCLAW_START_CMD with your actual Render/OpenClaw start command
OPENCLAW_START_CMD=${OPENCLAW_START_CMD:-"bash /app/entrypoint.sh"}

# Startup guard: exit with error if OPENCLAW_START_CMD is still placeholder
if [ "$OPENCLAW_START_CMD" = "YOUR_OPENCLAW_START_COMMAND_HERE" ]; then
    echo "ERROR: OPENCLAW_START_CMD is still the placeholder value"
    echo "Please set OPENCLAW_START_CMD environment variable to your actual OpenClaw start command"
    exit 1
fi

# Non-root paths (USER node, uid 1000)
SSH_DIR="/tmp/.ssh"
TAILSCALE_SOCKET_DIR="/tmp/tailscale"
TAILSCALE_STATE_FILE="/tmp/tailscale.state"

# Create SSH key from environment variable if provided
if [ -n "$VPS_SSH_KEY_B64" ]; then
    echo "Setting up SSH key from environment variable..."
    mkdir -p "$SSH_DIR"
    echo "$VPS_SSH_KEY_B64" | base64 -d > "$SSH_DIR/vps_key"
    chmod 600 "$SSH_DIR/vps_key"
    echo "IdentityFile $SSH_DIR/vps_key" > "$SSH_DIR/config"
    echo "StrictHostKeyChecking accept-new" >> "$SSH_DIR/config"
    chmod 600 "$SSH_DIR/config"
    export SSH_AUTH_SOCK=""
fi

# Start Tailscale in userspace mode if auth key is provided
if [ -n "$TAILSCALE_AUTHKEY" ]; then
    echo "Starting Tailscale in userspace mode..."
    mkdir -p "$TAILSCALE_SOCKET_DIR"

    tailscaled \
        --tun=userspace-networking \
        --socket="$TAILSCALE_SOCKET_DIR/tailscaled.sock" \
        --state="$TAILSCALE_STATE_FILE" \
        --socks5-server=127.0.0.1:${TS_SOCKS_PORT} &
    TAILSCALED_PID=$!

    sleep 2

    echo "Authenticating Tailscale..."
    if tailscale up \
        --socket="$TAILSCALE_SOCKET_DIR/tailscaled.sock" \
        --authkey="$TAILSCALE_AUTHKEY" \
        --hostname="$TS_HOSTNAME" \
        --accept-routes=false \
        --accept-dns=false; then
        echo "Tailscale authentication successful"

        echo "Tailscale status:"
        tailscale status --socket="$TAILSCALE_SOCKET_DIR/tailscaled.sock" || true
        echo "Tailscale IP:"
        tailscale ip --socket="$TAILSCALE_SOCKET_DIR/tailscaled.sock" || true

        echo "Testing VPS connectivity..."
        /app/check-vps-connectivity || echo "VPS connectivity test failed (non-fatal)"
    else
        echo "Tailscale authentication failed (non-fatal)"
        echo "Application will start without Tailscale connectivity"
    fi
else
    echo "TAILSCALE_AUTHKEY not set - skipping Tailscale setup"
    echo "Application will start without Tailscale connectivity"
fi

# Start the main OpenClaw application
echo "Starting OpenClaw: $OPENCLAW_START_CMD"
exec sh -lc "$OPENCLAW_START_CMD"