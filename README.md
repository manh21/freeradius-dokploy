# radius-dokploy

Dokploy template for deploying [FreeRADIUS](https://freeradius.org/) with a MariaDB backend and [daloRADIUS](https://github.com/lirantal/daloradius) web management panel.

## Stack

| Service | Source | Purpose |
|---|---|---|
| `radius-db` | `mariadb:10.11` | RADIUS user/NAS database |
| `freeradius` | `./freeradius` (custom build) | Authentication & accounting server |
| `daloradius` | `drakkan/daloradius:latest` | Web management UI |

The `freeradius` service is built from the local [`freeradius/`](freeradius/) directory. The custom image installs `freeradius-mysql` (the `rlm_sql_mysql` driver) and runs [`docker-entrypoint.sh`](freeradius/docker-entrypoint.sh) on startup to automatically:

1. Create the `mods-enabled/sql` and `mods-enabled/sqlcounter` symlinks.
2. Set the driver to `rlm_sql_mysql` and dialect to `mysql`.
3. Inject database connection details from environment variables into `mods-available/sql`.
4. Enable `read_clients` and `client_table` so NAS entries are read from the database.
5. Uncomment `sql` / `-sql` in the `authorize`, `accounting`, `post-auth`, and `session` sections of `sites-enabled/default`.

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| `1812` | UDP | RADIUS Authentication |
| `1813` | UDP | RADIUS Accounting |
| `8000` | TCP | daloRADIUS Web UI |

Ensure these ports are open on your VPS firewall before deploying.

## Deploy on Dokploy

1. Log into your Dokploy dashboard and create a new **Project**.
2. Add a **Compose** service and point it at this repository.
3. Under the **Environment** tab, add the variables from [`.env.example`](.env.example) with strong passwords.
4. Click **Deploy**. Dokploy will build the custom FreeRADIUS image and start all three services.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `MYSQL_ROOT_PASSWORD` | *(required)* | MariaDB root password |
| `MYSQL_DATABASE` | `radius` | Database name |
| `MYSQL_USER` | `radius` | Database user |
| `MYSQL_PASSWORD` | *(required)* | Database user password |

## Post-Deploy: Import the RADIUS Schema

FreeRADIUS requires specific tables. Import the schema bundled inside the `freeradius` container:

```sh
# Run this once from a terminal inside the freeradius container
mysql -h radius-db -u radius -p radius < /etc/raddb/mods-config/sql/main/mysql/schema.sql
```

Or via the `radius-db` container directly:

```sh
# Copy the schema out of the freeradius container first, then import
docker cp <freeradius-container>:/etc/raddb/mods-config/sql/main/mysql/schema.sql /tmp/radius.sql
mysql -h 127.0.0.1 -u radius -p radius < /tmp/radius.sql
```

daloRADIUS may also handle schema initialisation automatically on first login — check its container logs.

## Accessing daloRADIUS

Navigate to `http://<your-vps-ip>:8000` after deployment.

Default credentials (change immediately):
- **Username:** `administrator`
- **Password:** `radius`

## Dokploy-Specific Notes

- **Volumes** use the `../files/` prefix — the Dokploy convention for persistent bind-mount paths.
- The `raddb` config directory is **not** bind-mounted. A bind-mount of an empty host directory would shadow `/etc/raddb` entirely and prevent FreeRADIUS from starting. All SQL configuration is applied by the entrypoint script from environment variables at container startup.
- **No `container_name`** fields are set, which allows Dokploy to correctly aggregate logs.
- **`dokploy-network`** is declared as an external network so services can communicate within the Dokploy host ecosystem.
