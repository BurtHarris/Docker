# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# MediaWiki – the software that powers Wikipedia
#
# Extends the official mediawiki image with:
#   - Production PHP settings
#   - Site-specific PHP tuning (upload limits, memory, APCu)
#   - Apache logs routed to Docker stdout/stderr
#
# Version lifecycle: https://www.mediawiki.org/wiki/Version_lifecycle
# Official image:    https://hub.docker.com/_/mediawiki
# ---------------------------------------------------------------------------
ARG MEDIAWIKI_VERSION=1.43

FROM mediawiki:${MEDIAWIKI_VERSION}

# ---- Activate PHP production defaults --------------------------------------
# The PHP Docker image ships with php.ini-production but doesn't enable it;
# activating it tightens security defaults (error display off, etc.).
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini

# ---- Site-specific PHP tunables --------------------------------------------
# Override/extend the production defaults for MediaWiki's needs.
COPY config/php-wikimedia.ini /usr/local/etc/php/conf.d/wikimedia.ini

# ---- Route Apache logs to Docker stdout/stderr -----------------------------
# Containers should not write logs to files; let the Docker logging driver
# collect them instead.
RUN ln -sfT /dev/stderr /var/log/apache2/error.log \
 && ln -sfT /dev/stdout /var/log/apache2/access.log

# ---- Ensure the uploads directory exists with correct ownership ------------
RUN install -d -m 755 -o www-data -g www-data /var/www/html/images

EXPOSE 80

# Apache must start as root to bind port 80 then drops to www-data (uid 33).
# The healthcheck probes the API rather than Main_Page to avoid a full parse.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -fsS "http://localhost/api.php?action=query&format=json" || exit 1
