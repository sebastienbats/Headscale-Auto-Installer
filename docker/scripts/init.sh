#!/bin/bash
set -e

sleep 2

if ! headscale users list 2>/dev/null | grep -q "${HS_USER:-admin@headscale.internal}"; then
    echo "Creating user ${HS_USER:-admin@headscale.internal}..."
    headscale users create "${HS_USER:-admin@headscale.internal}" || true
fi

if ! headscale preauthkeys list --user "${HS_USER:-admin@headscale.internal}" 2>/dev/null | grep -q "reusable"; then
    echo "Creating pre-auth key..."
    headscale preauthkeys create --user "${HS_USER:-admin@headscale.internal}" --reusable --expiration 90d || true
fi

exec headscale serve -c /etc/headscale/config.yaml
