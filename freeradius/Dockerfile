FROM freeradius/freeradius-server:latest-alpine

# rlm_sql_mysql is a separate Alpine package not included in the base image.
# Pinning to latest-alpine because freeradius/freeradius-server:latest switched
# to Debian (no apk). The alpine variant is also ~half the image size (~44 MB).
RUN apk add --no-cache freeradius-mysql

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["freeradius", "-f"]
