#!/bin/bash
set -e

echo "-> Create empty common site config"
echo "{}" > /home/frappe/frappe-bench/sites/common_site_config.json

echo "-> Create new site with ERPNext"
bench new-site ${DFP_DOMAIN_NAME} \
  --admin-password="${DFP_SITE_ADMIN_PASSWORD}" \
  --mariadb-user-host-login-scope="172.%" \
  --db-root-username="root" \
  --db-root-password="${DFP_DB_ROOT_PASSWORD}" \
  --install-app="erpnext"
bench use ${DFP_DOMAIN_NAME}

echo "-> Enable scheduler"
bench enable-scheduler
