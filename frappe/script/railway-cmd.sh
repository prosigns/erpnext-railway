#!/bin/bash
set -e

if [ -z "$RFP_DOMAIN_NAME" ]; then
    echo "ERROR: RFP_DOMAIN_NAME is not set" >&2
    exit 1
fi

SITES_DIR="/home/frappe/frappe-bench/sites"

# Frappe derives the database name from the site name by replacing
# hyphens and dots with underscores.
_db_name() {
    echo "${RFP_DOMAIN_NAME}" | tr '.-' '_'
}

# External service connection settings. On Railway, services talk over private
# networking at "<service-name>.railway.internal", so these are the defaults.
export DB_HOST="${DB_HOST:-mariadb.railway.internal}"
export DB_PORT="${DB_PORT:-3306}"

require_var() {
    if [ -z "${!1}" ]; then
        echo "ERROR: $1 is not set" >&2
        exit 1
    fi
}

# Link the prebuilt assets + apps metadata from built_sites/ into sites/.
# railway-entrypoint.sh normally does this, BUT Railway's startCommand bypasses
# the image ENTRYPOINT, and once a Railway volume is mounted at sites/ it shadows
# the image's baked-in apps.txt/apps.json/assets. Without these links every bench
# command dies with "OSError: ./apps.txt Not Found". Recreated on every boot
# (idempotent) so it survives the empty-volume-on-first-boot case.
link_built_sites() {
    local bs="/home/frappe/frappe-bench/built_sites"
    echo "-> Linking built_sites assets into sites/"
    chown frappe:frappe "${SITES_DIR}" 2>/dev/null || true
    su frappe -c "rm -rf '${SITES_DIR}/assets' '${SITES_DIR}/apps.json' '${SITES_DIR}/apps.txt' \
        && ln -s '${bs}/assets' '${SITES_DIR}/assets' \
        && ln -s '${bs}/apps.json' '${SITES_DIR}/apps.json' \
        && ln -s '${bs}/apps.txt' '${SITES_DIR}/apps.txt'"

    # On a fresh/empty mounted volume sites/common_site_config.json does not
    # exist. `bench set-config -g` reads-then-merges that file, so it must be
    # present (even as an empty object) or every set-config call dies with
    # FileNotFoundError. configure_services() then fills in db_host + redis.
    su frappe -c "test -f '${SITES_DIR}/common_site_config.json' || echo '{}' > '${SITES_DIR}/common_site_config.json'"
}

# Point the site at the external MariaDB and Redis services. There is NO Redis
# inside this container, so without redis_cache / redis_queue the gunicorn web
# process and the bench workers cannot start — the :8000 upstream dies and nginx
# returns 502. Written on every boot (via bench set-config, which merges instead
# of clobbering) so the config always tracks the current service URLs.
configure_services() {
    require_var REDIS_CACHE_URL
    require_var REDIS_QUEUE_URL

    echo "-> Configuring MariaDB + Redis connections in common_site_config.json"
    su frappe -c "cd /home/frappe/frappe-bench \
        && bench set-config -g db_host '${DB_HOST}' \
        && bench set-config -gp db_port '${DB_PORT}' \
        && bench set-config -g redis_cache '${REDIS_CACHE_URL}' \
        && bench set-config -g redis_queue '${REDIS_QUEUE_URL}' \
        && bench set-config -g redis_socketio '${REDIS_QUEUE_URL}' \
        && bench set-config -gp socketio_port 9000"
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

# Reports whether SITES_DIR is backed by a mounted volume (persists across
# redeploys) or is just the container's ephemeral filesystem (wiped on every
# redeploy → site is recreated from scratch). A path is a mount point when its
# device id differs from its parent directory's device id.
report_persistence() {
    local dev_sites dev_parent
    dev_sites=$(stat -c %d "${SITES_DIR}" 2>/dev/null)
    dev_parent=$(stat -c %d "$(dirname "${SITES_DIR}")" 2>/dev/null)

    if [ -n "${dev_sites}" ] && [ "${dev_sites}" != "${dev_parent}" ]; then
        echo "-> Persistence: '${SITES_DIR}' IS a mounted volume — site data will survive redeploys."
    else
        echo "######################################################################" >&2
        echo "-> WARNING: '${SITES_DIR}' is NOT a mounted volume (ephemeral)." >&2
        echo "->          Your site will be RECREATED BLANK on every redeploy." >&2
        echo "->          Attach a Railway volume to this service at exactly:" >&2
        echo "->              ${SITES_DIR}" >&2
        echo "->          (and ensure the MariaDB service has its own volume)." >&2
        echo "######################################################################" >&2
    fi
}

link_built_sites

configure_services

report_persistence

if ! is_site_initialized; then
    echo "-> Site not fully initialized, running setup"
    /home/frappe/frappe-bench/railway-setup.sh
else
    echo "-> Site already initialized, ensuring HRMS + ZKTeco are installed"
    # App code is baked into the image (see Dockerfile); just make sure each app
    # is installed into this site's database (no-op if already installed).
    # ZKTeco after HRMS because it depends on erpnext + hrms.
    su frappe -c "bench --site ${RFP_DOMAIN_NAME} install-app hrms" 2>&1 || echo "HRMS installation completed or already installed"
    su frappe -c "bench --site ${RFP_DOMAIN_NAME} install-app zkteco_biometric_integration" 2>&1 || echo "ZKTeco installation completed or already installed"
fi

echo "-> Clearing cache"
su frappe -c "cd /home/frappe/frappe-bench && bench --site ${RFP_DOMAIN_NAME} execute frappe.cache_manager.clear_global_cache"

echo "-> Resolving paths"
BENCH_PATH=$(su frappe -c "which bench")
NODE_PATH=$(su frappe -c "which node")
export BENCH_PATH NODE_PATH

# Gunicorn concurrency for the web process. Tune via Railway env vars to match
# the container's CPU/RAM; defaults are a modest bump over the old 1 worker / 2 threads.
export GUNICORN_WORKERS="${GUNICORN_WORKERS:-2}"
export GUNICORN_THREADS="${GUNICORN_THREADS:-4}"

echo "-> Bursting env into config"
envsubst '$RFP_DOMAIN_NAME' < /home/frappe/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '$BENCH_PATH,$NODE_PATH,$GUNICORN_WORKERS,$GUNICORN_THREADS' < /home/frappe/temp_supervisor.conf > /home/frappe/supervisor.conf

# Remove the stock Debian default site. It binds `listen 80 default_server`, which
# both (a) collides with our default_server (nginx would fail to start) and
# (b) otherwise swallows the Railway healthcheck (Host: healthcheck.railway.app)
# and returns 404 on /api/method/ping.
rm -f /etc/nginx/sites-enabled/default

echo "-> Starting nginx"
nginx

echo "-> Starting supervisor"
/usr/bin/supervisord -c /home/frappe/supervisor.conf
