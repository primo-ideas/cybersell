#!/usr/bin/env bash
#
# Installs or updates Play Deals on Ubuntu 26.04: Postgres, the fetcher on a systemd
# timer, the site, and Caddy if given a domain. Safe to run again after a `git pull`.
#
#   sudo ./deploy/install.sh                                # site on 127.0.0.1:3000
#   sudo DOMAIN=trading.example.com ./deploy/install.sh     # site on https://trading.example.com
#   sudo DOMAIN=example.com BASE_PATH=/playdeals ./deploy/install.sh     # next to other sites
#
# Options, as environment variables. DOMAIN, BASE_PATH, OLD_BASE_PATH and WOW_DOMAIN are
# kept for the next runs:
#   DOMAIN        Public domain of the site. Its DNS must already point to this server.
#   BASE_PATH     Path of the site on that domain, when it shares it. Where Apache already
#                 runs, that path gets a route to the site, and nothing else changes. Without
#                 one, the Apache virtual host of the domain must send it all to the site.
#   OLD_BASE_PATH A path the site used to have on DOMAIN, or several separated by commas.
#                 Apache redirects each address under it to the same page under BASE_PATH.
#   WOW_DOMAIN    A domain the World of Warcraft pages used to have to themselves, or
#                 several separated by commas. Whatever serves it must send it all to the
#                 site, which then redirects each address to the same page under DOMAIN.
#   SCOPE         What to fetch on a first install, by default eu/commodities.
#   POLL_MINUTES  Minutes between two cycles, by default 5.
#
# See deploy/README.md.
set -euo pipefail

SCOPE="${SCOPE:-eu/commodities}"
POLL_MINUTES="${POLL_MINUTES:-5}"
DOMAIN="${DOMAIN:-}"
BASE_PATH="${BASE_PATH:-}"
OLD_BASE_PATH="${OLD_BASE_PATH:-}"
WOW_DOMAIN="${WOW_DOMAIN:-}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=/opt/playdeals
ETC=/etc/playdeals
BACKUP_DIR=/var/backups/playdeals
FETCHER_ENV="$ETC/fetcher.env"
SITE_ENV="$ETC/site.env"
SERVICE_USER=playdeals
OWNER_ROLE=playdeals
SITE_ROLE=playdeals_site
DATABASE=playdeals_wow
ACCOUNTS_DATABASE=playdeals_accounts
# Below this much memory and without swap, compiling can get killed.
SWAP_BELOW_MB=4000
SWAP_FILE=/swapfile
MAX_BUILD_JOBS=4
# A disk too small for the defaults: less swap and write-ahead log, a shorter hourly
# history, and no compiler left behind once the fetcher is built.
if [ "$(df --output=size -BG / | tail -n 1 | tr -dc 0-9)" -lt 16 ]; then
  SMALL_DISK=1 SWAP_SIZE=1G MAX_WAL_SIZE=256MB RETENTION_DAYS=7
else
  SMALL_DISK="" SWAP_SIZE=2G MAX_WAL_SIZE=1GB RETENTION_DAYS=14
fi

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this as root: sudo $0"
[ -f "$REPO/Cargo.toml" ] && [ -d "$REPO/web" ] || die "run this from a copy of the repository"
case "$POLL_MINUTES" in
  ''|*[!0-9]*) die "POLL_MINUTES must be a number of minutes" ;;
esac
[ "$POLL_MINUTES" -ge 1 ] && [ "$POLL_MINUTES" -le 59 ] || die "POLL_MINUTES must be between 1 and 59"

. /etc/os-release
[ "${VERSION_ID:-}" = "26.04" ] || printf 'warning: written for Ubuntu 26.04, this is %s\n' "${PRETTY_NAME:-unknown}" >&2

# Whoever ran sudo builds: compiling dependencies does not need to happen as root.
BUILD_USER="${SUDO_USER:-root}"
BUILD_HOME="$(getent passwd "$BUILD_USER" | cut -d: -f6)"
# sudo may leave HOME on root's, where rustup could not write.
as_builder() { runuser -u "$BUILD_USER" -- env -C "$REPO" HOME="$BUILD_HOME" "$@"; }

ensure_packages() {
  step "Installing packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # Not the `cargo` package: sqlx needs a newer Rust than Ubuntu 26.04 has, so rustup
  # installs the version named in rust-toolchain.toml.
  apt-get install -y -qq \
    build-essential cmake pkg-config git curl openssl ca-certificates tzdata \
    postgresql rustup \
    ruby ruby-dev libpq-dev libyaml-dev zlib1g-dev
}

ensure_swap() {
  local memory_mb
  memory_mb="$(awk '/MemTotal/ { print int($2 / 1024) }' /proc/meminfo)"
  if [ "$memory_mb" -ge "$SWAP_BELOW_MB" ] || [ -n "$(swapon --noheadings)" ]; then
    return
  fi
  step "Adding $SWAP_SIZE of swap ($memory_mb MB of memory)"
  if [ ! -f "$SWAP_FILE" ]; then
    fallocate -l "$SWAP_SIZE" "$SWAP_FILE"
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null
  fi
  swapon "$SWAP_FILE"
  grep -q "^$SWAP_FILE " /etc/fstab || echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
}

ensure_user() {
  id -u "$SERVICE_USER" >/dev/null 2>&1 || \
    useradd --system --home-dir "$APP" --shell /usr/sbin/nologin "$SERVICE_USER"
  install -d -m 755 "$APP" "$APP/bin"
  install -d -m 750 -o root -g "$SERVICE_USER" "$ETC"
}

psql_as_admin() { runuser -u postgres -- psql -v ON_ERROR_STOP=1 -q "$@"; }

role_exists() {
  [ "$(psql_as_admin -tAc "SELECT 1 FROM pg_roles WHERE rolname = '$1'")" = "1" ]
}

# Creates a role with a new password, written to stdout, if it does not exist yet.
ensure_role() {
  local role="$1" password
  if role_exists "$role"; then
    return
  fi
  password="$(openssl rand -hex 24)"
  psql_as_admin -c "CREATE ROLE $role LOGIN PASSWORD '$password'"
  printf '%s' "$password"
}

value_of() { sed -n "s/^$1=//p" "$2" | tail -n 1; }

# What an earlier run was given, so that `git pull && ./deploy/install.sh` keeps it.
load_saved_settings() {
  if [ -f "$SITE_ENV" ]; then
    [ -n "$DOMAIN" ] || DOMAIN="$(value_of SITE_HOST "$SITE_ENV")"
    [ -n "$BASE_PATH" ] || BASE_PATH="$(value_of RAILS_RELATIVE_URL_ROOT "$SITE_ENV")"
    [ -n "$OLD_BASE_PATH" ] || OLD_BASE_PATH="$(value_of OLD_BASE_PATH "$SITE_ENV")"
    [ -n "$WOW_DOMAIN" ] || WOW_DOMAIN="$(value_of WOW_HOSTS "$SITE_ENV")"
  fi
  check_base_path
  check_old_base_path
  [[ "$WOW_DOMAIN" =~ ^[A-Za-z0-9.,-]*$ ]] || die "WOW_DOMAIN must look like wow.example.com, not $WOW_DOMAIN"
  [ -z "$WOW_DOMAIN" ] || [ -n "$DOMAIN" ] || die "WOW_DOMAIN needs DOMAIN, where its addresses lead"
}

# Checked once read back as well: a file edited by hand may hold anything. The root of
# the domain is no path at all, as the site then has the domain to itself.
check_base_path() {
  while [ "${BASE_PATH%/}" != "$BASE_PATH" ]; do BASE_PATH="${BASE_PATH%/}"; done
  [[ "$BASE_PATH" =~ ^(/[A-Za-z0-9_-]+)*$ ]] || die "BASE_PATH must look like /playdeals, not $BASE_PATH"
}

# Only Apache's route on a shared domain redirects them: a domain of the site's own is its
# virtual host's job.
check_old_base_path() {
  [ -n "$OLD_BASE_PATH" ] || return 0
  [ -n "$BASE_PATH" ] || die "OLD_BASE_PATH needs BASE_PATH, the path its addresses lead to"
  local path
  for path in ${OLD_BASE_PATH//,/ }; do
    [[ "$path" =~ ^(/[A-Za-z0-9_-]+)+$ ]] || die "OLD_BASE_PATH must look like /ludeal, not $path"
    [ "$path" != "$BASE_PATH" ] || die "OLD_BASE_PATH cannot be BASE_PATH itself, $BASE_PATH"
  done
}

# An install from when the project had another name: wow-market, wow-trading, then
# Ludeal. Installing next to it would start from empty databases while its services kept
# the port and the history. Its directories move last, so that a run stopped halfway comes
# back here and finishes.
#
#   rename_old_install <name> <user and role> <market database> <accounts database> <fetcher>
rename_old_install() {
  local old="$1" old_user="$2" old_database="$3" old_accounts_database="$4" fetcher="$5"
  [ -d "/opt/$old" ] || [ -d "/etc/$old" ] || return 0
  step "Renaming the existing $old install to playdeals"

  local unit
  for unit in "$fetcher.timer" "$fetcher.service" site.service alerts.timer alerts.service backup.timer backup.service; do
    systemctl disable --now "$old-$unit" 2>/dev/null || true
    rm -f "/etc/systemd/system/$old-$unit"
  done
  systemctl daemon-reload

  if id -u "$old_user" >/dev/null 2>&1; then
    usermod --login "$SERVICE_USER" --home "$APP" "$old_user"
    groupmod --new-name "$SERVICE_USER" "$old_user"
  fi

  systemctl start postgresql
  # SCRAM passwords survive a rename, which is what Ubuntu's Postgres uses by default.
  rename_role "$old_user" "$OWNER_ROLE"
  rename_role "${old_user}_site" "$SITE_ROLE"
  rename_database "$old_database" "$DATABASE"
  rename_database "$old_accounts_database" "$ACCOUNTS_DATABASE"
  # ensure_database writes it again under its new name.
  rm -f /etc/postgresql/*/main/conf.d/"$old".conf

  # The same roles and databases, under their new names, in what the services read.
  local file
  for file in "/etc/$old/fetcher.env" "/etc/$old/site.env"; do
    if [ -f "$file" ]; then
      sed -i -E \
        -e "s#^(DATABASE_URL=postgres://)$old_user(_site)?:(.*/)$old_database\$#\\1$OWNER_ROLE\\2:\\3$DATABASE#" \
        -e "s#^(ACCOUNTS_DATABASE_URL=postgres://)${old_user}_site:(.*/)$old_accounts_database\$#\\1$SITE_ROLE:\\2$ACCOUNTS_DATABASE#" \
        "$file"
    fi
  done

  # The route this script gave Apache under the old name: configure_web_server writes
  # the new one, if the site still shares a domain.
  if [ -e "/etc/apache2/conf-enabled/$old.conf" ]; then
    a2disconf -q "$old"
    systemctl reload apache2
  fi
  rm -f "/etc/apache2/conf-available/$old.conf"

  if [ -d "/var/backups/$old" ] && [ ! -e "$BACKUP_DIR" ]; then
    mv "/var/backups/$old" "$BACKUP_DIR"
  fi
  if [ -d "/etc/$old" ]; then
    mv "/etc/$old" "$ETC"
  fi
  if [ -d "/opt/$old" ]; then
    # The fetcher has a new name too: it is built again rather than found under the old one.
    rm -f "/opt/$old/bin/$old-$fetcher" "/opt/$old/bin/.sources-hash"
    mv "/opt/$old" "$APP"
  fi
}

rename_role() {
  if role_exists "$1" && ! role_exists "$2"; then
    psql_as_admin -c "ALTER ROLE $1 RENAME TO $2"
  fi
}

database_exists() {
  [ "$(psql_as_admin -tAc "SELECT 1 FROM pg_database WHERE datname = '$1'")" = "1" ]
}

rename_database() {
  if database_exists "$1" && ! database_exists "$2"; then
    psql_as_admin -c "ALTER DATABASE $1 RENAME TO $2"
  fi
}

ensure_database() {
  step "Setting up Postgres"
  systemctl enable --now postgresql

  local owner_password site_password
  owner_password="$(ensure_role "$OWNER_ROLE")"
  site_password="$(ensure_role "$SITE_ROLE")"

  if ! database_exists "$DATABASE"; then
    runuser -u postgres -- createdb --owner "$OWNER_ROLE" --encoding UTF8 --locale C --template template0 "$DATABASE"
  fi

  # The site can read whatever the fetcher creates, including its daily partitions, and nothing else.
  psql_as_admin -d "$DATABASE" <<SQL
GRANT CONNECT ON DATABASE $DATABASE TO $SITE_ROLE;
GRANT USAGE ON SCHEMA public TO $SITE_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $SITE_ROLE;
ALTER DEFAULT PRIVILEGES FOR ROLE $OWNER_ROLE IN SCHEMA public GRANT SELECT ON TABLES TO $SITE_ROLE;
SQL

  # What players save: the only database the site writes to, which it owns. Unlike market
  # snapshots, none of it can be fetched again, so a commit must really be on disk.
  if ! database_exists "$ACCOUNTS_DATABASE"; then
    runuser -u postgres -- createdb --owner "$SITE_ROLE" --encoding UTF8 --locale C --template template0 "$ACCOUNTS_DATABASE"
  fi
  psql_as_admin -c "ALTER DATABASE $ACCOUNTS_DATABASE SET synchronous_commit = on"

  local version conf memory_mb shared_buffers
  version="$(psql_as_admin -tAc "SHOW server_version_num" | cut -c1-2)"
  conf="/etc/postgresql/$version/main/conf.d/playdeals.conf"
  memory_mb="$(awk '/MemTotal/ { print int($2 / 1024) }' /proc/meminfo)"
  shared_buffers=$(( memory_mb / 4 ))
  # Losing the last commits in a crash is fine: the next cycle gets those snapshots again.
  cat > "$conf" <<CONF
# Written by deploy/install.sh.
shared_buffers = ${shared_buffers}MB
effective_cache_size = $(( memory_mb / 2 ))MB
max_wal_size = $MAX_WAL_SIZE
synchronous_commit = off
CONF
  systemctl restart postgresql

  # Credentials are kept across runs: an update must not need them typed again.
  if [ ! -f "$FETCHER_ENV" ]; then
    [ -n "$owner_password" ] || die "role $OWNER_ROLE exists but $FETCHER_ENV does not: restore it, or drop the role"
    install -m 640 -o root -g "$SERVICE_USER" /dev/null "$FETCHER_ENV"
    cat > "$FETCHER_ENV" <<ENV
# Create a client on https://develop.battle.net/access/clients
BLIZZARD_CLIENT_ID=
BLIZZARD_CLIENT_SECRET=

# What to fetch: eu, eu/hyjal, eu/commodities, or several separated by commas.
# Each market takes around 1 GB of disk: see deploy/README.md before adding many.
WOW_SCOPE=$SCOPE
WOW_LOCALE=en_US
WOW_HOURLY_RETENTION_DAYS=$RETENTION_DAYS

DATABASE_URL=postgres://$OWNER_ROLE:$owner_password@127.0.0.1:5432/$DATABASE
ENV
  fi

  if [ ! -f "$SITE_ENV" ]; then
    [ -n "$site_password" ] || die "role $SITE_ROLE exists but $SITE_ENV does not: restore it, or drop the role"
    install -m 640 -o root -g "$SERVICE_USER" /dev/null "$SITE_ENV"
    cat > "$SITE_ENV" <<ENV
DATABASE_URL=postgres://$SITE_ROLE:$site_password@127.0.0.1:5432/$DATABASE
SECRET_KEY_BASE=$(openssl rand -hex 64)
ENV
  fi

  # An install from before accounts: same role and password, in the database of its own.
  if ! grep -q '^ACCOUNTS_DATABASE_URL=' "$SITE_ENV"; then
    echo "ACCOUNTS_DATABASE_URL=$(value_of DATABASE_URL "$SITE_ENV" | sed -E 's#/[^/]*$##')/$ACCOUNTS_DATABASE" >> "$SITE_ENV"
  fi
  if ! grep -q 'SMTP_ADDRESS=' "$SITE_ENV"; then
    cat >> "$SITE_ENV" <<ENV

# To email players when a product reaches its target price. Without it, the site does
# not offer alerts. Run the install again after setting these.
# SMTP_ADDRESS=smtp.example.com
# SMTP_PORT=587
# SMTP_USERNAME=
# SMTP_PASSWORD=
# MAIL_FROM=alerts@example.com
ENV
  fi

  # Set on every run, as a domain can be added later.
  sed -i '/^SITE_HOST=/d;/^RAILS_RELATIVE_URL_ROOT=/d;/^OLD_BASE_PATH=/d;/^WOW_HOSTS=/d' "$SITE_ENV"
  if [ -n "$DOMAIN" ]; then
    echo "SITE_HOST=$DOMAIN" >> "$SITE_ENV"
  fi
  if [ -n "$BASE_PATH" ]; then
    echo "RAILS_RELATIVE_URL_ROOT=$BASE_PATH" >> "$SITE_ENV"
  fi
  if [ -n "$OLD_BASE_PATH" ]; then
    echo "OLD_BASE_PATH=$OLD_BASE_PATH" >> "$SITE_ENV"
  fi
  if [ -n "$WOW_DOMAIN" ]; then
    echo "WOW_HOSTS=$WOW_DOMAIN" >> "$SITE_ENV"
  fi

  # Signing in with Battle.net uses the fetcher's client. Only those two lines of its file,
  # which also holds the password of the role that can write the market data.
  sed -i '/^BLIZZARD_CLIENT_ID=/d;/^BLIZZARD_CLIENT_SECRET=/d' "$SITE_ENV"
  echo "BLIZZARD_CLIENT_ID=$(value_of BLIZZARD_CLIENT_ID "$FETCHER_ENV")" >> "$SITE_ENV"
  echo "BLIZZARD_CLIENT_SECRET=$(value_of BLIZZARD_CLIENT_SECRET "$FETCHER_ENV")" >> "$SITE_ENV"
}

# A copy of the databases as they are, before an update changes them. A first install,
# which has no backup script yet, has nothing to lose. The script is this version's: the
# one of an install that was just renamed still names the old databases.
backup_before_update() {
  [ -x "$APP/bin/backup.sh" ] && [ -d "$BACKUP_DIR" ] || return 0
  step "Backing up before the update"
  runuser -u postgres -- env -C / BACKUP_DIR="$BACKUP_DIR" bash -s < "$REPO/deploy/backup.sh"
}

# Each compiler can take over a gigabyte: fewer at a time is slower, but it finishes.
build_jobs() {
  local memory_mb jobs
  memory_mb="$(awk '/MemTotal/ { print int($2 / 1024) }' /proc/meminfo)"
  jobs=$(( memory_mb / 1500 + 1 ))
  [ "$jobs" -le "$(nproc)" ] || jobs="$(nproc)"
  [ "$jobs" -le "$MAX_BUILD_JOBS" ] || jobs="$MAX_BUILD_JOBS"
  printf '%s' "$jobs"
}

fetcher_sources_hash() {
  (cd "$REPO" && find fetcher Cargo.toml Cargo.lock rust-toolchain.toml -type f -print0 |
    sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}

build_fetcher() {
  local hash toolchain
  hash="$(fetcher_sources_hash)"
  # Without a change there, an update of the site need not take a compilation.
  if [ -x "$APP/bin/playdeals-wow-fetcher" ] && [ "$(cat "$APP/bin/.sources-hash" 2>/dev/null)" = "$hash" ]; then
    step "The fetcher has not changed: not building it again"
    return
  fi

  step "Building the fetcher (several minutes the first time, more on a small server)"
  toolchain="$(sed -n 's/^channel = "\(.*\)"$/\1/p' "$REPO/rust-toolchain.toml")"
  [ -n "$toolchain" ] || die "no toolchain named in rust-toolchain.toml"

  as_builder rustup toolchain install "$toolchain" --profile minimal --no-self-update
  # `rustup run` rather than `cargo`, which the rustup package may not put on the PATH.
  as_builder rustup run "$toolchain" cargo build --release --locked --jobs "$(build_jobs)" -p playdeals-wow-fetcher
  install -m 755 "$REPO/target/release/playdeals-wow-fetcher" "$APP/bin/playdeals-wow-fetcher"
  printf '%s' "$hash" > "$APP/bin/.sources-hash"

  # All of this comes back at the next build, which then only costs time.
  if [ -n "$SMALL_DISK" ]; then
    step "Removing the compiler and its output, as this disk is small"
    rm -rf "$REPO/target" "$BUILD_HOME/.cargo/registry"
    as_builder rustup toolchain uninstall "$toolchain"
    apt-get clean
  fi
}

build_site() {
  step "Building the site"
  install -d -m 755 "$APP/web"
  # A clean copy, keeping only the gems already installed.
  find "$APP/web" -mindepth 1 -maxdepth 1 ! -name vendor -exec rm -rf {} +
  tar -C "$REPO/web" --exclude=./log --exclude=./tmp --exclude=./vendor --exclude=./test -cf - . | tar -C "$APP/web" -xf -
  install -d -m 755 "$APP/web/vendor" "$APP/web/.bundle"
  install -d -m 755 -o "$SERVICE_USER" -g "$SERVICE_USER" "$APP/web/tmp" "$APP/web/log"

  (
    cd "$APP/web"
    # Ubuntu's Ruby may know of Bundler without a `bundle` command: install the one the
    # lockfile names, so that it does not try to swap itself for it at each start.
    local bundler_version
    bundler_version="$(sed -n '/^BUNDLED WITH$/{n;s/ *//p}' Gemfile.lock)"
    [ -n "$bundler_version" ] || die "no Bundler version named in Gemfile.lock"
    gem list --installed --exact bundler --version "$bundler_version" >/dev/null 2>&1 ||
      gem install --no-document bundler --version "$bundler_version"
    export BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development:test BUNDLE_PATH=vendor/bundle
    bundle config set --local deployment true
    bundle config set --local without development:test
    bundle config set --local path vendor/bundle
    bundle install --quiet --jobs "$(build_jobs)"
    # Compiling assets touches neither the database nor the secret, but Rails wants both set.
    # The path matters here: compiled stylesheets refer to their fonts by full path.
    RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 DATABASE_URL=postgres://unused/unused \
      ACCOUNTS_DATABASE_URL=postgres://unused/unused \
      RAILS_RELATIVE_URL_ROOT="$BASE_PATH" bundle exec rails assets:precompile
  )
}

# With the very environment the site runs in, read by systemd rather than a shell: values
# like MAIL_FROM may hold spaces.
migrate_accounts() {
  step "Migrating the accounts database"
  systemd-run --quiet --wait --pipe --collect \
    --uid="$SERVICE_USER" --gid="$SERVICE_USER" --working-directory="$APP/web" \
    --property=EnvironmentFile="$SITE_ENV" \
    --setenv=RAILS_ENV=production --setenv=BUNDLE_DEPLOYMENT=1 \
    /usr/bin/env bundle exec rails db:migrate
}

install_units() {
  step "Installing the systemd units"
  install -m 644 "$REPO/deploy/playdeals-wow-fetcher.service" /etc/systemd/system/
  install -m 644 "$REPO/deploy/playdeals-site.service" /etc/systemd/system/
  install -m 644 "$REPO/deploy/playdeals-alerts.service" /etc/systemd/system/
  install -m 644 "$REPO/deploy/playdeals-backup.service" "$REPO/deploy/playdeals-backup.timer" /etc/systemd/system/
  install -m 755 "$REPO/deploy/backup.sh" "$APP/bin/backup.sh"
  install -d -m 700 -o postgres -g postgres "$BACKUP_DIR"
  sed "s|^OnCalendar=.*|OnCalendar=*:0/$POLL_MINUTES|" "$REPO/deploy/playdeals-wow-fetcher.timer" \
    > /etc/systemd/system/playdeals-wow-fetcher.timer
  chmod 644 /etc/systemd/system/playdeals-wow-fetcher.timer
  # Two minutes after the fetcher's, to find what it has just stored.
  sed "s|^OnCalendar=.*|OnCalendar=*:2/$POLL_MINUTES|" "$REPO/deploy/playdeals-alerts.timer" \
    > /etc/systemd/system/playdeals-alerts.timer
  chmod 644 /etc/systemd/system/playdeals-alerts.timer
  systemctl daemon-reload
}

configure_web_server() {
  [ -n "$DOMAIN" ] || return 0
  if systemctl is-active --quiet apache2; then
    configure_apache
  else
    configure_caddy
  fi
}

APACHE_ROUTE=/etc/apache2/conf-available/playdeals.conf
APACHE_ROUTE_ENABLED=/etc/apache2/conf-enabled/playdeals.conf

# Apache already answers here: Caddy could not take its ports, and the domain may serve
# other things. The route below applies to every domain Apache serves, so it only ever
# claims a path, never the root: a domain of the site's own is its virtual host's job.
configure_apache() {
  local vhost
  vhost="$(apache_vhost_of "$DOMAIN")"
  [ -n "$vhost" ] || die "Apache has no virtual host for $DOMAIN, so no certificate to serve it with"

  if [ -z "$BASE_PATH" ]; then
    remove_apache_route
    grep -q '127\.0\.0\.1:3000' "$vhost" ||
      die "Apache serves $DOMAIN from $vhost, which does not send it to the site: add ProxyPass / http://127.0.0.1:3000/ to it, or give the site a path of its own with BASE_PATH, like /playdeals"
    step "Apache sends https://$DOMAIN to the site from $vhost: leaving it as it is"
    return
  fi

  step "Configuring Apache for https://$DOMAIN$BASE_PATH"
  a2enmod -q proxy proxy_http headers alias
  cat > "$APACHE_ROUTE" <<APACHE
# Written by deploy/install.sh.
<Location "$BASE_PATH">
	ProxyPreserveHost On
	ProxyPass "http://127.0.0.1:3000$BASE_PATH"
	ProxyPassReverse "http://127.0.0.1:3000$BASE_PATH"
	RequestHeader set X-Forwarded-Proto "https"
</Location>
APACHE
  # Where the site used to be: links and bookmarks lead to the same page, query included.
  local path
  for path in ${OLD_BASE_PATH//,/ }; do
    printf 'RedirectMatch permanent "^%s(/.*)?$" "%s$1"\n' "$path" "$BASE_PATH" >> "$APACHE_ROUTE"
  done
  a2enconf -q playdeals
  if ! apache2ctl configtest 2>/dev/null; then
    a2disconf -q playdeals
    die "Apache refuses this configuration: it was disabled again, and Apache left running as it was"
  fi
  # New modules take a restart.
  systemctl restart apache2
}

# The configuration file of the virtual host that serves this domain over HTTPS: the
# one on port 80, if any, only sends visitors there.
apache_vhost_of() {
  apache2ctl -S 2>/dev/null | grep -F "port 443 namevhost $1 (" | sed -n 's/.*(\(.*\):[0-9]*)$/\1/p' | head -n 1
}

# Left by a run that served the site on a path of a shared domain.
remove_apache_route() {
  [ -e "$APACHE_ROUTE_ENABLED" ] || return 0
  grep -q 'Written by deploy/install.sh' "$APACHE_ROUTE" 2>/dev/null || return 0
  step "Removing the Apache route of an earlier install, which every domain of this server got"
  a2disconf -q playdeals
  systemctl reload apache2
}

configure_caddy() {
  step "Configuring Caddy for $DOMAIN"
  apt-get install -y -qq caddy
  local caddyfile=/etc/caddy/Caddyfile
  if [ -f "$caddyfile" ] && ! grep -q 'Written by deploy/install.sh' "$caddyfile"; then
    cp "$caddyfile" "$caddyfile.before-playdeals"
  fi
  cat > "$caddyfile" <<CADDY
# Written by deploy/install.sh.
$DOMAIN {
	encode zstd gzip
	reverse_proxy 127.0.0.1:3000
}
CADDY
  systemctl enable caddy
  systemctl reload-or-restart caddy
}

has_credentials() {
  [ -n "$(value_of BLIZZARD_CLIENT_ID "$FETCHER_ENV")" ] && [ -n "$(value_of BLIZZARD_CLIENT_SECRET "$FETCHER_ENV")" ]
}

start_services() {
  systemctl enable playdeals-site.service
  systemctl restart playdeals-site.service
  systemctl enable playdeals-wow-fetcher.timer

  systemctl enable --now playdeals-backup.timer
  # Without waiting for the night: a new install deserves a first backup too.
  if [ -z "$(ls -A "$BACKUP_DIR")" ]; then
    systemctl start --no-block playdeals-backup.service
  fi

  # Starting Rails every few minutes is only worth it with a way to send the emails.
  if [ -n "$(value_of SMTP_ADDRESS "$SITE_ENV")" ]; then
    systemctl enable playdeals-alerts.timer
    systemctl restart playdeals-alerts.timer
  else
    systemctl disable --now playdeals-alerts.timer 2>/dev/null || true
  fi

  if has_credentials; then
    systemctl restart playdeals-wow-fetcher.timer
    # Without waiting for it: a first cycle takes minutes. Not an error if one is running.
    systemctl start --no-block playdeals-wow-fetcher.service
    step "Done. Check with: sudo $REPO/deploy/check.sh"
    if [ -n "$DOMAIN" ]; then
      printf 'For players to sign in, add this redirect URL to your client on develop.battle.net:\n  https://%s%s/auth/battlenet/callback\n' "$DOMAIN" "$BASE_PATH"
    fi
  else
    systemctl stop playdeals-wow-fetcher.timer
    step "Almost done: Battle.net credentials are missing"
    cat <<TEXT
1. Create a client on https://develop.battle.net/access/clients
2. Fill in BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET:
     sudo nano $FETCHER_ENV
3. Start fetching:
     sudo systemctl enable --now playdeals-wow-fetcher.timer
     sudo systemctl start --no-block playdeals-wow-fetcher.service
4. Run this script again, so that players can sign in with that client too.
5. Check with:
     sudo $REPO/deploy/check.sh
TEXT
  fi

  if [ -n "$WOW_DOMAIN" ]; then
    printf 'Every address of %s now leads to https://%s%s/wow, as long as what serves it sends it all to the site.\n' \
      "$WOW_DOMAIN" "$DOMAIN" "$BASE_PATH"
  fi

  if [ -z "$DOMAIN" ]; then
    cat <<TEXT

The site listens on this server only. To see it from your computer:
  ssh -L 3000:127.0.0.1:3000 <server>
then open http://127.0.0.1:3000. To serve it publicly, run this script again with DOMAIN set.
TEXT
  fi
}

ensure_packages
rename_old_install wow-market wowmarket wow_market wow_market_accounts fetcher
rename_old_install wow-trading wowtrading wow_trading wow_trading_accounts fetcher
rename_old_install ludeal ludeal ludeal_wow ludeal_accounts wow-fetcher
load_saved_settings
ensure_swap
ensure_user
ensure_database
backup_before_update
build_fetcher
build_site
migrate_accounts
install_units
configure_web_server
start_services
