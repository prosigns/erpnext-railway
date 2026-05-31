#!/bin/bash
set -e

echo "-> Create symlinks for apps.txt & apps.json"
ln -sf /home/frappe/frappe-bench/apps.json /home/frappe/frappe-bench/sites/apps.json
ln -sf /home/frappe/frappe-bench/apps.txt /home/frappe/frappe-bench/sites/apps.txt
ln -sf /home/frappe/frappe-bench/assets /home/frappe/frappe-bench/sites/assets

if [ "${DFP_DISABLE_STARTUP:-}" = "DISABLE_STARTUP" ]; then
  echo "-> Startup disabled, sleeping"
  exec sleep infinity
fi

exec "$@"