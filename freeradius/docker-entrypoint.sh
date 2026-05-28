#!/bin/sh
set -e

RADDB=/etc/raddb
SQL_MOD="$RADDB/mods-available/sql"
SQL_LINK="$RADDB/mods-enabled/sql"
SQLCOUNTER_MOD="$RADDB/mods-available/sqlcounter"
SQLCOUNTER_LINK="$RADDB/mods-enabled/sqlcounter"
EXPIRATION_LINK="$RADDB/mods-enabled/expiration"
# Edit the source file directly — sed -i on a symlink replaces the symlink
# with a new regular file, leaving sites-available/default untouched.
SITES_AVAILABLE="$RADDB/sites-available/default"
SITES_LINK="$RADDB/sites-enabled/default"
COUNTER_DIR="$RADDB/mods-config/sql/counter/mysql"

# ── 1. Enable module symlinks ────────────────────────────────────────────────
[ ! -e "$SQL_LINK" ] && ln -s "$SQL_MOD" "$SQL_LINK"

[ -f "$SQLCOUNTER_MOD" ] && [ ! -e "$SQLCOUNTER_LINK" ] && \
    ln -s "$SQLCOUNTER_MOD" "$SQLCOUNTER_LINK"

# expiration module enforces the Expiration check attribute
[ -f "$RADDB/mods-available/expiration" ] && [ ! -e "$EXPIRATION_LINK" ] && \
    ln -s "$RADDB/mods-available/expiration" "$EXPIRATION_LINK"

# Ensure sites-enabled/default symlink points at sites-available/default
[ ! -e "$SITES_LINK" ] && ln -s "$SITES_AVAILABLE" "$SITES_LINK"

# ── 2. Configure SQL module ──────────────────────────────────────────────────
sed -i -E 's|^(\s*driver\s*=\s*)"[^"]*"|\1"rlm_sql_mysql"|' "$SQL_MOD"
sed -i -E 's|^(\s*dialect\s*=\s*)"[^"]*"|\1"mysql"|'        "$SQL_MOD"

# Re-applied on every restart so env var changes take effect without a rebuild
sed -i -E "s|^(\s*server\s*=\s*)\"[^\"]*\"|\1\"${RADIUS_DB_HOST:-localhost}\"|"  "$SQL_MOD"
sed -i -E "s|^(\s*port\s*=\s*)[0-9]+|\1${RADIUS_DB_PORT:-3306}|"                 "$SQL_MOD"
sed -i -E "s|^(\s*login\s*=\s*)\"[^\"]*\"|\1\"${RADIUS_DB_USER:-radius}\"|"      "$SQL_MOD"
sed -i -E "s|^(\s*password\s*=\s*)\"[^\"]*\"|\1\"${RADIUS_DB_PASS}\"|"           "$SQL_MOD"
sed -i -E "s|^(\s*radius_db\s*=\s*)\"[^\"]*\"|\1\"${RADIUS_DB_NAME:-radius}\"|"  "$SQL_MOD"

sed -i -E 's|^(\s*)#\s*(read_clients\s*=\s*yes)|\1\2|'   "$SQL_MOD"
sed -i -E 's|^(\s*)#\s*(client_table\s*=\s*"nas")|\1\2|' "$SQL_MOD"

# ── 3. Append billing counter definitions to sqlcounter module ───────────────
# accessperiod — elapsed time since the user's very first session start
if ! grep -q 'sqlcounter accessperiod' "$SQLCOUNTER_MOD" 2>/dev/null; then
    cat >> "$SQLCOUNTER_MOD" << 'EOF'

sqlcounter accessperiod {
    sql_module_instance = sql
    dialect = ${modules.sql.dialect}
    counter_name = Max-Access-Period-Time
    check_name = Access-Period
    key = User-Name
    reset = never
    $INCLUDE ${modconfdir}/sql/counter/${dialect}/${.:instance}.conf
}
EOF
fi

# quotalimit — cumulative upload + download bytes across all sessions
if ! grep -q 'sqlcounter quotalimit' "$SQLCOUNTER_MOD" 2>/dev/null; then
    cat >> "$SQLCOUNTER_MOD" << 'EOF'

sqlcounter quotalimit {
    sql_module_instance = sql
    dialect = ${modules.sql.dialect}
    counter_name = Max-Volume
    check_name = Max-Data
    reply_name = Mikrotik-Total-Limit
    key = User-Name
    reset = never
    $INCLUDE ${modconfdir}/sql/counter/${dialect}/${.:instance}.conf
}
EOF
fi

# uptimelimit — total session time across all sessions (inline query, no .conf file needed)
if ! grep -q 'sqlcounter uptimelimit' "$SQLCOUNTER_MOD" 2>/dev/null; then
    cat >> "$SQLCOUNTER_MOD" << 'EOF'

sqlcounter uptimelimit {
    sql_module_instance = sql
    dialect = ${modules.sql.dialect}
    counter_name = Max-All-Session-Time
    check_name = Max-All-Session
    key = User-Name
    reset = never
    query = "SELECT SUM(AcctSessionTime) FROM radacct WHERE UserName='%{${key}}'"
}
EOF
fi

# ── 4. Create SQL query files for accessperiod and quotalimit counters ────────
mkdir -p "$COUNTER_DIR"

cat > "$COUNTER_DIR/accessperiod.conf" << 'EOF'
query = "SELECT UNIX_TIMESTAMP() - UNIX_TIMESTAMP(AcctStartTime) FROM radacct WHERE UserName='%{${key}}' ORDER BY AcctStartTime LIMIT 1"
EOF

cat > "$COUNTER_DIR/quotalimit.conf" << 'EOF'
query = "SELECT (SUM(acctinputoctets) + SUM(acctoutputoctets)) FROM radacct WHERE UserName='%{${key}}'"
EOF

# ── 5. Enable sql in virtual server sections ─────────────────────────────────
# Uncomments lines that are whitespace + "#" + optional whitespace + "-sql" or "sql"
sed -i -E 's|^(\s*)#\s*(-?sql)\s*$|\1\2|' "$SITES_AVAILABLE"

# ── 6. Add billing counters to the authorize section ─────────────────────────
# Inserted after the -sql call so they run after the user record is fetched
if ! grep -qE '^\s*quotalimit\s*$' "$SITES_AVAILABLE"; then
    awk '
    /^authorize[[:space:]]*\{/ { in_auth=1 }
    in_auth && /^[[:space:]]*-sql[[:space:]]*$/ {
        print $0
        print "\texpiration"
        print "\tquotalimit"
        print "\taccessperiod"
        print "\tuptimelimit"
        in_auth=0
        next
    }
    { print }
    ' "$SITES_AVAILABLE" > /tmp/sites_default.tmp \
        && mv /tmp/sites_default.tmp "$SITES_AVAILABLE"
fi

exec "$@"
