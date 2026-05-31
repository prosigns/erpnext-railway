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

# Returns 0 (true) if `bench new-site` completed on a previous run.
# A finished site has its db_name written into site_config.json, so we detect
# that directly. We deliberately do NOT shell out to the `mysql` CLI to probe
# MariaDB: that client is not installed in this image, so the old probe ALWAYS
# returned false and drove an endless new-site crash loop ("Site already
# exists, use --force"). bench creates the DB via Python, not the mysql CLI.
is_site_initialized() {
    local site_config="${SITES_DIR}/${RFP_DOMAIN_NAME}/site_config.json"

    if [ -f "${site_config}" ] && grep -q '"db_name"' "${site_config}"; then
        return 0
    fi

    return 1
}

if is_site_initialized; then
    echo "-> Site ${RFP_DOMAIN_NAME} is already initialized, skipping site creation"
else
    # A leftover, half-created site directory (dir present but no db_name in
    # site_config.json) would make `bench new-site` abort with "Site already
    # exists". Pass --force so it cleanly drops/recreates the stale site + DB.
    # This branch only runs when the site is NOT initialized, so --force can
    # never clobber a good site.
    echo "-> Create new site with ERPNext"
    su frappe -c "bench new-site ${RFP_DOMAIN_NAME} --force --admin-password ${RFP_SITE_ADMIN_PASSWORD} --no-mariadb-socket --db-root-password ${FRAPPE_DB_PASSWORD} --install-app erpnext"
    su frappe -c "bench --site ${RFP_DOMAIN_NAME} set-config socketio_port 9000"
    su frappe -c "bench use ${RFP_DOMAIN_NAME}"

    echo "-> Enable scheduler"
    # Run as frappe and scoped to the site; guarded so a non-zero exit can't
    # abort the script (set -e) after the site was already created.
    su frappe -c "bench --site ${RFP_DOMAIN_NAME} enable-scheduler" 2>&1 || echo "Warning: could not enable scheduler (continuing)"
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
