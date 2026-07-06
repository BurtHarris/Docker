# Wikimedia (MediaWiki) Docker Stack

[MediaWiki](https://www.mediawiki.org/) is the open-source wiki software that
powers Wikipedia and thousands of other wikis.

This stack runs MediaWiki + MariaDB in Docker containers and is suitable for
both local development and self-hosted production deployments.

## What's included

| File | Purpose |
|---|---|
| `Dockerfile` | Extends the official `mediawiki:1.43` image with production PHP settings |
| `docker-compose.yml` | Base stack (mediawiki + mariadb) |
| `docker-compose.override.yml` | Dev overrides (auto-loaded by Compose) — exposes port 8080 |
| `docker-compose.prod.yml` | Production overrides — connect to external reverse proxy |
| `.env.example` | Template for required environment variables |
| `config/php-wikimedia.ini` | PHP tunables copied into the image at build time |
| `LocalSettings.example.php` | Annotated MediaWiki configuration template |

## Quick start (development)

### 1. Copy and fill in the environment file

```bash
cp .env.example .env
```

Edit `.env` and replace the placeholder values.  At minimum set:

```bash
DB_PASSWORD=<strong password>
MW_SECRET_KEY=<output of: openssl rand -hex 32>
MW_UPGRADE_KEY=<output of: openssl rand -hex 8>
```

### 2. Build and start the stack

```bash
docker compose up -d --build
```

The wiki will be accessible at <http://localhost:8080> once the database health
check passes (usually 30–60 seconds).

### 3. Run the installer

**Option A — Web installer (recommended for first time):**

1. Open <http://localhost:8080> in your browser.
2. Follow the wizard.  When asked for the database host, enter `database`.
3. At the end, download the generated `LocalSettings.php`.
4. Place `LocalSettings.php` next to this `docker-compose.yml`.
5. Uncomment the `LocalSettings.php` volume line in `docker-compose.yml`.
6. Restart: `docker compose restart mediawiki`

**Option B — CLI installer (scriptable / CI-friendly):**

```bash
docker compose exec mediawiki php /var/www/html/maintenance/install.php \
  --dbname  "${DB_NAME:-my_wiki}"   \
  --dbserver database               \
  --dbuser  "${DB_USER:-wikiuser}"  \
  --dbpass  "${DB_PASSWORD}"        \
  --lang    en                      \
  --pass    "${ADMIN_PASSWORD}"     \
  "My Wiki" "admin"
```

The script writes `LocalSettings.php` inside the container at
`/var/www/html/LocalSettings.php`.  Copy it out:

```bash
docker compose cp mediawiki:/var/www/html/LocalSettings.php ./LocalSettings.php
```

Then add the `getenv()` calls from `LocalSettings.example.php` so passwords
are never stored in the file.

### 4. (Optional) Customise LocalSettings.php

Use `LocalSettings.example.php` as a reference.  Key settings:

- `$wgServer` — must match the URL users type in their browser
- `$wgSitename` — displayed in the browser title bar and header
- `$wgGroupPermissions` — controls who can read/edit/create accounts

## Production deployment

Use the `docker-compose.prod.yml` override together with a reverse proxy
(Caddy, Traefik, or nginx) that handles TLS termination.

```bash
# Create the shared proxy network once:
docker network create proxy_net

docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  up -d --build
```

In `docker-compose.prod.yml`, set `internal_net.internal: true` to prevent
the database from being reachable from the internet.

In `LocalSettings.php` set:

```php
$wgServer = 'https://wiki.example.com';
```

## Upgrading MediaWiki

1. Edit the `MEDIAWIKI_VERSION` build arg in `docker-compose.yml` (or `Dockerfile`).
2. Rebuild: `docker compose build`
3. Restart: `docker compose up -d`
4. Run the database update script:

```bash
docker compose exec mediawiki php /var/www/html/maintenance/update.php
```

## Common operations

| Task | Command |
|---|---|
| View logs | `docker compose logs -f mediawiki` |
| Open a shell | `docker compose exec mediawiki bash` |
| Backup the database | `docker compose exec database sh -c 'mariadb-dump -u root --all-databases' > backup.sql` |
| Restore the database | `docker compose exec -T database sh -c 'mariadb -u root' < backup.sql` |
| Rebuild the image | `docker compose build --no-cache mediawiki` |
| Stop the stack | `docker compose down` |
| Destroy all data | `docker compose down -v` (⚠️ deletes volumes) |

## Volumes

| Volume | Default name | Contents |
|---|---|---|
| `mediawiki_images` | `mywiki_images` | User-uploaded files |
| `db_data` | `mywiki_db` | MariaDB data files |

Both volume names are prefixed with `WIKI_NAME` from `.env`, so you can run
multiple independent wikis on the same host without collisions.

## References

- [MediaWiki Docker documentation](https://www.mediawiki.org/wiki/MediaWiki-Docker)
- [Official Docker Hub image](https://hub.docker.com/_/mediawiki)
- [LocalSettings.php reference](https://www.mediawiki.org/wiki/Manual:LocalSettings.php)
- [MediaWiki version lifecycle](https://www.mediawiki.org/wiki/Version_lifecycle)
