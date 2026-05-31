# ------------------------------------------
# - Stage: 01 - builder
# ------------------------------------------

# This image is also based on frappe/bench which we use for production
# https://github.com/pipech/erpnext-docker-debian/blob/master/Dockerfile
FROM thspacecode/erpnext-docker:version-16-latest AS builder

RUN echo "-> Start builder" \
    ## install apps
    && bench get-app print_designer --branch main \
    && echo "-> Builder done!"

# ------------------------------------------
# - Stage: 02 - production
# ------------------------------------------

# Image version should also match with stage 01
# (Check pipech/erpnext-docker-debian Dockerfile)
# https://github.com/frappe/frappe_docker/blob/main/images/bench/Dockerfile
FROM frappe/base:version-16

# Copied bench folder from build stage
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

COPY --chmod=0755 ./.prodcontainer/frappe/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 ./.prodcontainer/frappe/init.sh /usr/local/bin/init.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

EXPOSE 80
