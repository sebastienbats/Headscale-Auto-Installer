#!/bin/bash
set -e

sleep 2

if ! headscale users list | grep -q "${HS_USER:-admin}"; then
    echo "Creating user ${HS_USER:-admin}..."
    headscale users create "${HS_USER:-admin}" || true
fi

if ! headscale preauthkeys list --user "${HS_USER:-admin}" | grep -q "reusable"; then
    echo "Creating pre-auth key..."
    headscale preauthkeys create --user "${HS_USER:-admin}" --reusable --expiration 90d || true
fi

exec headscale serve -c /etc/headscale/config.yaml
