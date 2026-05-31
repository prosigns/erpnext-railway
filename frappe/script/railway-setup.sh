#!/bin/bash
set -e

require_var() {
    if [ -z "${!1}" ]; then
        echo "ERROR: $1 is not set" >&2
        exit 1
    fi
}

require_var RFP_DOMAIN_NAME
require_var RFP_SITE_ADMIN_PASSWORD
require_var FRAPPE_DB_PASSWORD

SITES_DIR="/home/frappe/frappe-bench/sites"

# Frappe derives the database name from the site name by replacing
# hyphens and dots with underscores.
_db_name() {
    echo "${RFP_DOMAIN_NAME}" | tr '.-' '_'
}

# Returns 0 (true) if the site is fully initialized:
#   1. The site directory exists
#   2. site_config.json is present
#   3. The MariaDB database exists and contains the tabDocType table,
#      confirming that `bench new-site` completed successfully.
is_site_initialized() {
    local site_config="${SITES_DIR}/${RFP_DOMAIN_NAME}/site_config.json"
    local db_name
    db_name=$(_db_name)

    # Fast-path: directory or config missing → not initialized
    if [ ! -d "${SITES_DIR}/${RFP_DOMAIN_NAME}" ] || [ ! -f "${site_config}" ]; then
        return 1
    fi

    # Verify the database actually has Frappe's core table.
    # Uses the MariaDB root password so this works even when the
    # per-site DB user was not yet created (e.g. partial setup).
    if mysql -h "${DB_HOST:-mariadb}" -P "${DB_PORT:-3306}" \
             -u root -p"${FRAPPE_DB_PASSWORD}" \
             --connect-timeout=10 --silent --skip-column-names \
             -e "SELECT 1 FROM information_schema.tables
                 WHERE table_schema = '${db_name}'
                   AND table_name   = 'tabDocType'
                 LIMIT 1;" 2>/dev/null | grep -q "1"; then
        return 0
    fi

    echo "-> Site directory exists but database '${db_name}' is not initialized" >&2
    return 1
}

if is_site_initialized; then
    echo "-> Site ${RFP_DOMAIN_NAME} is already initialized (directory + database verified), skipping site creation"
else
    # NOTE: common_site_config.json (db_host + redis_*) is written by
    # configure_services() in railway-cmd.sh BEFORE this script runs, so
    # bench new-site connects to the external MariaDB/Redis correctly.
    echo "-> Create new site with ERPNext"
    su frappe -c "bench new-site ${RFP_DOMAIN_NAME} --admin-password ${RFP_SITE_ADMIN_PASSWORD} --no-mariadb-socket --db-root-password ${FRAPPE_DB_PASSWORD} --install-app erpnext"
    su frappe -c "bench --site ${RFP_DOMAIN_NAME} set-config socketio_port 9000"
    su frappe -c "bench use ${RFP_DOMAIN_NAME}"

    echo "-> Enable scheduler"
    bench enable-scheduler
fi

echo "-> Install HRMS app into the site"
# The HRMS app code is already baked into the image (see Dockerfile), so we only
# need to install it into the site's database here.
su frappe -c "bench --site ${RFP_DOMAIN_NAME} install-app hrms" 2>&1 || echo "HRMS installation completed or already installed"

echo "-> Install ZKTeco Biometric Integration app into the site"
# App code is baked into the image (see Dockerfile); install it into the site's
# database here. Installed AFTER hrms because it depends on erpnext + hrms.
su frappe -c "bench --site ${RFP_DOMAIN_NAME} install-app zkteco_biometric_integration" 2>&1 || echo "ZKTeco installation completed or already installed"

echo "-> Disable automatic user creation for Employee (prevents broken welcome email template)"
# Write a small Python script to a temp file to avoid shell-escaping issues with bench execute
PATCH_SCRIPT=$(mktemp /tmp/frappe_patch_XXXXXX.py)
cat > "${PATCH_SCRIPT}" << 'PYEOF'
import frappe

frappe.db.sql(
    "UPDATE `tabDocField` SET `default`='0'"
    " WHERE parent='Employee' AND fieldname='create_user_automatically'"
)
frappe.db.commit()
print("create_user_automatically default set to 0 on Employee DocType")
PYEOF
chown frappe:frappe "${PATCH_SCRIPT}"
su frappe -c "cd /home/frappe/frappe-bench && bench --site ${RFP_DOMAIN_NAME} execute-script ${PATCH_SCRIPT}" 2>&1 || \
    echo "Warning: Could not disable create_user_automatically; employees may trigger a broken welcome email on save"
rm -f "${PATCH_SCRIPT}"
