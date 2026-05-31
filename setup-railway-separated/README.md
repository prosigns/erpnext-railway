# Deploy and Host ERPNext on Railway

## What is ERPNext?

[ERPNext](https://erpnext.com/) is a free, open-source ERP (Enterprise Resource Planning) system designed for small and medium businesses.
Built on the [Frappe framework](https://frappe.io/), it provides integrated modules for accounting, HR, CRM, inventory, manufacturing, and project management.

## About Hosting ERPNext

Hosting ERPNext involves deploying the Frappe framework along with its essential services: MariaDB for data storage, Redis for caching and queuing, and a reverse proxy like Nginx.

On Railway, you can containerize ERPNext, configure environment variables, and attach persistent storage volumes for durability.

### Service Overview

![frappe-service-overfiew](https://ik.imagekit.io/caffeinnne/random/railway-frappe-arch_9_7rYuCfW.png)

## Common Use Cases

- Running a centralized ERP system for small to mid-sized companies.

## Deployment Guide

1. Deploy this template to Railway.
1. [Optional] Configure volume backups for both Frappe and MariaDB volumes. See [Railway Backups Documentation](https://docs.railway.com/reference/backups)
 for details.

## Dependencies for ERPNext Hosting

- [MariaDB](https://mariadb.org/) – Database backend.
- [Redis](http://redis.io/) – Caching and job queue management.

### Deployment Dependencies

- [Official ERPNext Docker](https://github.com/frappe/frappe_docker)
- [Frappe Framework / ERPNext Architecture](https://spacecode.co.th/knowledge-base/p/erpnext-system-architect)

## Why Deploy ERPNext on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying ERPNext on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.

## FAQ / Limitation

**Q:** What is `administrator` password?

**A:** Admin password can be found from `RFP_SITE_ADMIN_PASSWORD` variable on `erpnext-docker` container.

--

**Q:** Why is Supervisor used?

**A:** Railway currently limits each volume to a single service. Since multiple ERPNext services need to access the same volume, Supervisor is required to coordinate and share volumes across services (as of 2025-09-15).

Ref: [Railway | Shared Volumes](https://station.railway.com/feedback/shared-volumes-a4053215)

--

**Q:** Why use slightly older versions of Redis?

**A:** We use the versions defined in the official Frappe Docker images to ensure maximum compatibility with ERPNext and its dependencies.

Ref: [Frappe-Docker | pwd.yml](https://github.com/frappe/frappe_docker/blob/5cdd428a665214ea7d058250ffadabae4ae91226/pwd.yml#L167-L183)
