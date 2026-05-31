# Base image is overridable so builds can be pinned for reproducibility.
# The default tracks the moving "version-16-latest" tag; for production pin to a
# digest, e.g. ERPNEXT_IMAGE=thspacecode/erpnext-docker@sha256:<digest>
# (set it as a Railway build variable, or `--build-arg` locally).
ARG ERPNEXT_IMAGE=thspacecode/erpnext-docker:version-16-latest
FROM ${ERPNEXT_IMAGE}

USER root

RUN apt-get update \
    && apt-get install -y -q \
    # [fix] "debconf: delaying package configuration, since apt-utils is not installed"
    apt-utils \
    # [fix] "debconf: unable to initialize frontend: Dialog"
    # https://github.com/moby/moby/issues/27988
    && echo "debconf debconf/frontend select Noninteractive" | debconf-set-selections \
    ###############################################
    # add sudo
    ###############################################
    && apt-get install -y -q sudo \
    && echo "frappe ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
    ###############################################
    # add supervisor
    ###############################################
    && apt-get install -y -q \
    supervisor \
    nginx \
    ###############################################
    # clean-up
    ###############################################
    && apt-get autoremove --purge -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/*

# Bake the HRMS and ZKTeco biometric apps into the image at build time so they are
# NOT re-cloned from GitHub on every container boot. This only fetches + builds the
# app code and its assets; installing into a site's database still happens at runtime
# (see railway-setup.sh / railway-cmd.sh) because the site lives on the volume.
# Done BEFORE the built_sites copy below so the apps' assets + apps.txt are included.
# Order matters: hrms before zkteco, which depends on erpnext + hrms.
USER frappe
# Seed socketio_port into sites/common_site_config.json BEFORE building the apps.
# HRMS's v16 PWA frontend (frontend/src/socket.js) does a static named import of
# `socketio_port` from common_site_config.json; rollup requires the key to exist
# at build time or `bench build --app hrms` fails with
#   "socketio_port" is not exported by ".../common_site_config.json"
RUN cd /home/frappe/frappe-bench \
    && bench set-config -gp socketio_port 9000 \
    && bench get-app hrms https://github.com/frappe/hrms --branch version-16 \
    && bench get-app zkteco_biometric_integration https://github.com/navariltd/zkteco-biometric-integration --branch version-16

USER root

# copy built_sites from sites
RUN mkdir -p /home/frappe/frappe-bench/built_sites \
    && cp -r /home/frappe/frappe-bench/sites/assets /home/frappe/frappe-bench/built_sites/assets \
    && cp /home/frappe/frappe-bench/sites/apps.json /home/frappe/frappe-bench/built_sites/apps.json \
    && cp /home/frappe/frappe-bench/sites/apps.txt /home/frappe/frappe-bench/built_sites/apps.txt \
    && chown -R frappe:frappe /home/frappe/frappe-bench/built_sites

# copy template
COPY ./template/temp_nginx.conf /home/frappe/temp_nginx.conf
COPY ./template/temp_supervisor.conf /home/frappe/temp_supervisor.conf

# copy script
COPY --chown=frappe --chmod=0755 ./script/railway-setup.sh /home/frappe/frappe-bench/railway-setup.sh
COPY --chown=frappe --chmod=0755 ./script/railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY --chown=frappe --chmod=0755 ./script/railway-cmd.sh /usr/local/bin/railway-cmd.sh

USER root

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/usr/local/bin/railway-cmd.sh"]

EXPOSE 80
