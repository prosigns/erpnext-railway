# ERPNext on Railway

Deploy [ERPNext](https://erpnext.com/) (built on the [Frappe framework](https://frappe.io/))
to [Railway](https://railway.com/) as a set of separated services.

All deployment files live in **[`frappe/`](./frappe/)**.
Start with its [README](./frappe/README.md) for the full step-by-step guide.

## Architecture

ERPNext runs as **four Railway services**:

| Service | What it runs | Volume |
|---|---|---|
| **frappe** ([`frappe/`](./frappe/)) | nginx + Supervisor (gunicorn web, socket.io, workers, scheduler) | Required at `/home/frappe/frappe-bench/sites` |
| **mariadb** | MariaDB database (must use `utf8mb4`) | Required |
| **redis-cache** | Redis cache | Optional |
| **redis-queue** | Redis job queue + socket.io pub/sub | Optional |

Web, workers, and scheduler share one container via Supervisor because Railway allows
only one volume per service.

## Quick start

1. Point a Railway service at this repo with **Root Directory** = `frappe`.
2. Add the **mariadb**, **redis-cache**, and **redis-queue** services.
3. Attach volumes to **frappe** (`/home/frappe/frappe-bench/sites`) and **mariadb**.
4. Set the required environment variables (see the
   [setup guide](./frappe/README.md#deployment-guide)).
5. Deploy.

See **[`frappe/README.md`](./frappe/README.md)** for the
complete guide, including the required MariaDB charset configuration, the full
environment-variable table, and troubleshooting.

## Credits

Based on the [official Frappe Docker](https://github.com/frappe/frappe_docker) images.
