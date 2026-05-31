# Deploy and Host ERPNext on Railway

## What is ERPNext?

[ERPNext](https://erpnext.com/) is a free, open-source ERP (Enterprise Resource Planning) system designed for small and medium businesses.
Built on the [Frappe framework](https://frappe.io/), it provides integrated modules for accounting, HR, CRM, inventory, manufacturing, and project management.

## About Hosting ERPNext

Hosting ERPNext involves deploying the Frappe framework along with its essential services: MariaDB for data storage, Redis for caching and queuing, and a reverse proxy like Nginx.

On Railway, you can containerize ERPNext, configure environment variables, and attach persistent storage volumes for durability.

### Service Overview

![frappe-service-overfiew](https://ik.imagekit.io/caffeinnne/random/railway-frappe-arch_9_7rYuCfW.png)

This template runs ERPNext as **four Railway services**:

| Service | What it runs | Volume |
|---|---|---|
| **frappe** (this Dockerfile) | nginx + Supervisor (gunicorn web, socket.io, default/short/long workers, scheduler) | **Required** at `/home/frappe/frappe-bench/sites` |
| **mariadb** | MariaDB 10.6 database | **Required** at the DB data dir |
| **redis-cache** | Redis for cache | Optional |
| **redis-queue** | Redis for the job queue + socket.io pub/sub | Optional |

> Why is everything except the DB/Redis in one container? Railway currently allows
> only **one volume per service**, and the Frappe web, workers, and scheduler all
> need the same `sites` volume. Supervisor coordinates them inside a single service.
> See [Railway | Shared Volumes](https://station.railway.com/feedback/shared-volumes-a4053215).

## Common Use Cases

- Running a centralized ERP system for small to mid-sized companies.

---

## Deployment Guide

### 1. Create the MariaDB service ⚠️ read this carefully

ERPNext **will not initialize** against a default MariaDB. The database server must
use the `utf8mb4` character set. Create a MariaDB service and set its **custom start
command** (Settings → Deploy → Custom Start Command, or the image's `command`) to:

```
--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --skip-character-set-client-handshake
```

Set the root password variable on the MariaDB service (the exact name depends on the
image you pick):

```
MARIADB_ROOT_PASSWORD = <choose-a-strong-password>
# or, for the mysql-style images:  MYSQL_ROOT_PASSWORD = <same-value>
```

Attach a **volume** to MariaDB for its data directory.

> The value you choose here must be reused as `FRAPPE_DB_PASSWORD` on the frappe
> service — site creation runs `bench new-site` with `--db-root-password`, so it
> needs the MariaDB **root** password.

### 2. Create the redis-cache and redis-queue services

Add two Redis services (`redis-cache` and `redis-queue`). The official Frappe images
pin specific Redis versions for compatibility — using those tags is recommended (see
FAQ below). No public domain or volume is required; they are reached over Railway
private networking.

### 3. Create the frappe service (this repo)

Point a new service at this repository / the `setup-railway-separated` directory.
Railway will build the [Dockerfile](./Dockerfile) (config in [railway.json](./railway.json)).

**Attach a volume** to the frappe service mounted at exactly:

```
/home/frappe/frappe-bench/sites
```

Without this, your site is **recreated blank on every redeploy** (the startup script
prints a loud warning if the mount is missing).

**Set the service target port to `80`** (Settings → Networking). nginx listens on
port 80 inside the container.

#### Required environment variables (frappe service)

| Variable | Required | Description |
|---|---|---|
| `RFP_DOMAIN_NAME` | ✅ | The site name. Use the domain you'll actually serve from (e.g. `erp.example.com`, or the generated `xxxx.up.railway.app`). nginx pins all requests to this single site, so any inbound domain resolves to it. |
| `RFP_SITE_ADMIN_PASSWORD` | ✅ | Password for the `Administrator` login. |
| `FRAPPE_DB_PASSWORD` | ✅ | **Must equal the MariaDB root password** from step 1. |
| `REDIS_CACHE_URL` | ✅ | e.g. `redis://redis-cache.railway.internal:6379` |
| `REDIS_QUEUE_URL` | ✅ | e.g. `redis://redis-queue.railway.internal:6379` |
| `DB_HOST` | optional | Defaults to `mariadb.railway.internal`. Override if your MariaDB service has a different name. |
| `DB_PORT` | optional | Defaults to `3306`. |
| `GUNICORN_WORKERS` | optional | Web worker processes. Default `2`. Raise on larger instances. |
| `GUNICORN_THREADS` | optional | Threads per worker. Default `4`. |
| `ERPNEXT_IMAGE` | optional | **Build** variable. Pin the base image to a digest for reproducible builds, e.g. `thspacecode/erpnext-docker@sha256:<digest>`. |

> Use Railway's [reference variables](https://docs.railway.com/guides/variables#reference-variables)
> to wire `REDIS_CACHE_URL` / `REDIS_QUEUE_URL` / `FRAPPE_DB_PASSWORD` to the other
> services instead of copy-pasting values.

### 4. First deploy

On the first boot the frappe service runs `bench new-site` and installs `erpnext` +
`hrms`. This can take several minutes; the healthcheck timeout is set to `1200s`
(20 min) in [railway.json](./railway.json) to accommodate it. Subsequent redeploys
reuse the site on the volume and start fast.

### 5. [Optional] Configure volume backups

Configure volume backups for both the **frappe** and **mariadb** volumes. See
[Railway Backups Documentation](https://docs.railway.com/reference/backups).

---

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

**Q:** What is the `administrator` password?

**A:** The admin password is the value of the `RFP_SITE_ADMIN_PASSWORD` variable on the `frappe` service.

--

**Q:** I get "Site not found" or a blank/redirect loop when opening the app.

**A:** Make sure `RFP_DOMAIN_NAME` is set. nginx pins every request to that single
site via the `X-Frappe-Site-Name` header, so it works regardless of whether you
reach it via the `*.up.railway.app` domain or a custom domain. You do **not** need
`RFP_DOMAIN_NAME` to match the public URL.

--

**Q:** The first deploy fails during site creation with a charset / collation error.

**A:** Your MariaDB service isn't configured for `utf8mb4`. Re-check step 1 — the
custom start command must include `--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci`.

--

**Q:** My site is blank after a redeploy.

**A:** The `frappe` service is missing its volume (or it isn't mounted at
`/home/frappe/frappe-bench/sites`). The startup logs print a `WARNING: ... is NOT a
mounted volume` banner when this happens.

--

**Q:** Why is Supervisor used?

**A:** Railway currently limits each volume to a single service. Since multiple ERPNext services need to access the same volume, Supervisor is required to coordinate and share volumes across services (as of 2025-09-15).

Ref: [Railway | Shared Volumes](https://station.railway.com/feedback/shared-volumes-a4053215)

--

**Q:** Why use slightly older versions of Redis?

**A:** We use the versions defined in the official Frappe Docker images to ensure maximum compatibility with ERPNext and its dependencies.

Ref: [Frappe-Docker | pwd.yml](https://github.com/frappe/frappe_docker/blob/5cdd428a665214ea7d058250ffadabae4ae91226/pwd.yml#L167-L183)

--

**Q:** Can I run more than one replica of the frappe service?

**A:** No. Keep `numReplicas: 1`. The container also runs the Frappe **scheduler**;
multiple replicas would execute scheduled jobs more than once and corrupt data.
Scale vertically (more CPU/RAM + higher `GUNICORN_WORKERS`) instead.
