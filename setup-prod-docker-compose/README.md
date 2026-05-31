# Production Setup - Docker Compose

## Prerequisites

- [Docker Engine](https://docs.docker.com/engine/install/)
- Clone this repository

## Setup

**1. Create `.env` file**

```env
DFP_DOMAIN_NAME=erp.example.com
DFP_DB_ROOT_PASSWORD=your_root_password
DFP_SITE_ADMIN_PASSWORD=your_admin_password
```

**2. Build and start**

```bash
docker compose build
docker compose up -d
```

**3. Initialize site**

```bash
docker compose exec fp-web init.sh
```

**4. Restart**

```bash
docker compose restart
```

## Notes

- Nginx listens on port 80. Place a reverse proxy (e.g. Traefik, Caddy) in front for TLS termination.
