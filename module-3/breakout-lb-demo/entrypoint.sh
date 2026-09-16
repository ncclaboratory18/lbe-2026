#!/bin/sh
set -e

# VM_HOSTNAME is expected to be passed in at "docker run" time, e.g.:
#   docker run -d -e VM_HOSTNAME=$(whoami) -p 8080:8080 breakout-lb-demo
#
# We sanitize it down to only what a Linux whoami can legally contain
# (letters, digits, hyphen) before writing it into a JS file. This avoids
# any chance of breaking the generated script or injecting something
# unexpected into the page.
SAFE_HOSTNAME=$(printf '%s' "${VM_HOSTNAME:-unknown}" | tr -cd 'A-Za-z0-9-')

if [ -z "$SAFE_HOSTNAME" ]; then
  SAFE_HOSTNAME="unknown"
fi

cat > /usr/share/nginx/html/config.js <<EOF
window.APP_CONFIG = { hostname: "${SAFE_HOSTNAME}" };
EOF

echo "Starting Breakout LB demo, whoami injected as: ${SAFE_HOSTNAME}"

exec nginx -g "daemon off;"
