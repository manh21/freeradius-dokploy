FROM freeradius/freeradius-server:latest

# rlm_sql_mysql is a separate Alpine package not included in the base image
RUN apk add --no-cache freeradius-mysql

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["freeradius", "-f"]
