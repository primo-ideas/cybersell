#!/usr/bin/env bash
#
# Saves what cannot be fetched again: the accounts, in full, and the long-term history
# of the market data. Started each night by playdeals-backup.timer: see deploy/README.md.
#
# Left out of the market data, and 99% of its size: the hourly detail of the last days,
# and what the fetcher works out again at its next snapshot.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/playdeals}"
# Days of accounts kept, to go back to before a mistake: they are small.
KEEP_DAYS="${KEEP_DAYS:-14}"
# The market history only grows, so yesterday's copy is inside today's: the latest, and
# one more in case it turns out bad, are enough. Each holds all of it, and grows with it.
KEEP_MARKET="${KEEP_MARKET:-2}"
ACCOUNTS_DATABASE="${ACCOUNTS_DATABASE:-playdeals_accounts}"
MARKET_DATABASE="${MARKET_DATABASE:-playdeals_wow}"

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
# Names sort by day.
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'accounts-*.dump' -o -name '*.part' \) -mtime +"$KEEP_DAYS" -delete
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'market-*.dump' | sort | head -n -"$KEEP_MARKET" | xargs -r rm -f --
