#!/usr/bin/env bash
#
# Saves what cannot be fetched again: the accounts, in full, and the long-term history
# of the market data. Started each night by wow-trading-backup.timer: see deploy/README.md.
#
# Left out of the market data, and 99% of its size: the hourly detail of the last days,
# and what the fetcher works out again at its next snapshot.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/wow-trading}"
KEEP_DAYS="${KEEP_DAYS:-14}"
ACCOUNTS_DATABASE="${ACCOUNTS_DATABASE:-wow_trading_accounts}"
MARKET_DATABASE="${MARKET_DATABASE:-wow_trading}"

# Accounts hold email addresses.
umask 077
day="$(date -u +%Y-%m-%d)"

# Under another name until read back: a dump cut short must never pass for a good one.
dump() {
  local name="$1" file
  shift
  file="$BACKUP_DIR/$name-$day.dump"
  if ! pg_dump --format=custom --file="$file.part" "$@" || ! pg_restore --list "$file.part" >/dev/null; then
    rm -f "$file.part"
    echo "backup of the $name failed: the previous ones are kept" >&2
    return 1
  fi
  mv -f "$file.part" "$file"
  printf '%s: %s bytes\n' "$file" "$(wc -c < "$file")"
}

dump accounts --dbname="$ACCOUNTS_DATABASE"
dump market --dbname="$MARKET_DATABASE" \
  --exclude-table-data='public.price_points_2*' \
  --exclude-table-data='public.sales_points_2*' \
  --exclude-table-data=public.market_states \
  --exclude-table-data=public.listed_products

# Only once both have succeeded: backups that keep failing must not eat the good ones.
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name '*.dump' -o -name '*.part' \) -mtime +"$KEEP_DAYS" -delete
