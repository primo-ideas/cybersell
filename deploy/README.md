# Deploy to a server

For a small Ubuntu 26.04 server, for example a Scaleway instance. A single script installs everything: Postgres, the fetcher and its timer, the site, and Caddy for HTTPS if you give it a domain.

> **Run on one server so far,** under Ubuntu 26.04 with Apache already in front. Installing Caddy, on a server without Apache, has not been tried, nor have alerts through an SMTP server. Neither has [renaming an install from wow-trading](#updating-an-install-from-before-a-rename), which is new. The script is written to be safely run again: if it fails, fix the cause and run it again.

## Install

Plan for about 20 GB of disk for the commodities and one realm, compilation included. The repository must be reachable from the server.

```sh
git clone <repository-url> ludeal
cd ludeal
sudo SCOPE=eu/commodities,eu/hyjal ./deploy/install.sh
```

Expect several minutes: the fetcher compiles on the spot. The script adds 2 GB of swap if the server has less than 4 GB of memory and no swap, and limits simultaneous compilations to 4, fewer on a small server.

It then stops and asks for the Battle.net credentials:

1. Create a client on <https://develop.battle.net/access/clients>.
2. Fill in `BLIZZARD_CLIENT_ID` and `BLIZZARD_CLIENT_SECRET`, without quotes:

   ```sh
   sudo nano /etc/ludeal/fetcher.env
   ```

3. Start it, then check:

   ```sh
   sudo systemctl enable --now ludeal-wow-fetcher.timer
   sudo systemctl start --no-block ludeal-wow-fetcher.service
   sudo ./deploy/install.sh
   sudo ./deploy/check.sh
   ```

   Running the script a second time gives the site that same client, for players to sign in. See [Accounts](#accounts).

`check.sh` says what works and what does not, and shows no secret: its output can be shared to ask for help.

### See the site

By default, the site only listens on the server. From your computer, go through an SSH tunnel, then open <http://127.0.0.1:3000>:

```sh
ssh -L 3000:127.0.0.1:3000 <server>
```

To make it public, point the domain's DNS to the server, open ports 80 and 443 in its Scaleway security group, then run the script again. Caddy obtains and renews the certificate on its own:

```sh
sudo DOMAIN=trading.example.com ./deploy/install.sh
```

Once public, anyone can read the market pages: accounts are optional, and only hold what players save. The site cannot change the market data, as its Postgres role only has read access to it.

### Next to other sites

If the domain serves other things, give the site a path of its own. Where Apache already runs, with a certificate for that domain, the script adds a route to it in `/etc/apache2/conf-available/ludeal.conf`, and neither installs Caddy nor changes anything else:

```sh
sudo DOMAIN=example.com BASE_PATH=/ludeal ./deploy/install.sh
```

That route applies to every domain Apache serves on the server, which is why it only ever claims a path. To give the site a domain of its own on such a server, give that domain an Apache virtual host that sends everything to the site, for example with `ProxyPass / http://127.0.0.1:3000/` next to the certificate Certbot adds, then run the script with `DOMAIN` alone. It checks that virtual host, leaves it as it is, and removes the route of an earlier run on a path:

```sh
sudo DOMAIN=trading.example.com ./deploy/install.sh
```

The script remembers `DOMAIN`, `BASE_PATH` and `WOW_DOMAIN` for the next runs. A path of `/` counts as none.

### A domain the World of Warcraft pages had to themselves

Before the site covered several games, its World of Warcraft pages could be a whole domain, with `/eu/hyjal` where the site now has `/wow/eu/hyjal`. Name that domain, and the site redirects each of its addresses to the same page under `DOMAIN`, so that links and bookmarks keep working:

```sh
sudo DOMAIN=example.com BASE_PATH=/ludeal WOW_DOMAIN=trading.example.com ./deploy/install.sh
```

Whatever serves the old domain must still send all of it to the site, as it did until then: with Apache, a virtual host with its certificate and `ProxyPass / http://127.0.0.1:3000/`. The script does not touch it, and `check.sh` says whether the redirect works. Several domains are separated by commas.

What readers kept in their browser on the old domain does not follow them: the realm they picked, a watchlist without an account, and their session, so they sign in again. What is in an account is untouched.

### On an IPv6-only server

Battle.net and GitHub have no IPv6 address. Without an IPv4 address on the server, the fetcher cannot reach Battle.net, and `check.sh` says so: attach one, for example a flexible IP on Scaleway, and also add an `A` record for readers without IPv6.

To install or update such a server, send the code from your computer rather than cloning it:

```sh
git bundle create - HEAD | ssh root@server 'cat > ludeal.bundle'
ssh root@server 'git clone ludeal.bundle ludeal'
```

For an update, replace the second command with `git -C ludeal pull ../ludeal.bundle HEAD`.

## When the fetcher runs

**A systemd timer, every 5 minutes.**

Blizzard publishes once an hour. On November 5, 2026, the 93 European markets all changed at the same time, at 10:21:54, 11:21:53 and 12:21:53 UTC. That is few measurements: a single day, a single region.

- **Why not once an hour, at the right minute:** nothing guarantees that this minute stays the same, or that it is the same in other regions. A minute off would lose an hour of data.
- **Why asking often costs nothing:** each request carries `If-Modified-Since`, and Blizzard answers 304 without data as long as nothing has changed. New snapshots thus arrive less than 5 minutes after they are published.
- **Why not more often:** the data does not change any faster. And each cycle looks up to 1,000 new items, which is 2,000 requests: at 5 minutes, this stays under Battle.net's limit of 36,000 requests per hour.
- **Why systemd rather than cron:** a cycle still running is not started again on top of itself, logs go to the journal, the start order with Postgres is handled, and the fetcher runs with no rights beyond the network and its database.

To change the interval, run the script again:

```sh
sudo POLL_MINUTES=10 ./deploy/install.sh
```

## Size the server

These figures come from real snapshots of `eu/commodities` and `eu/hyjal`, and a simulated history of the same size, as no market has two weeks of real data yet.

| | |
| --- | --- |
| Site | 130 MB of memory (measured on Windows) |
| Fetcher | 110 MB at the peak of a cycle, 20 MB without a new snapshot |
| Postgres | A quarter of the server's memory, set by the script |
| Disk, per market | About 1 GB for 14 days of hourly detail |
| Disk, daily summaries | About 2 MB per day and per market, never purged |

2 GB of memory should be comfortable for the commodities and one or two realms. On 1 GB, it should work with the swap, without guarantee: this has not been measured. Page times have not been measured on a small server either.

On a disk under 16 GB, the script adapts: 1 GB of swap instead of 2, less write-ahead log, 7 days of hourly detail, and it removes the Rust compiler and its output once the fetcher is built. They come back at the next update of the fetcher, which then takes as long as the first build.

If disk runs short, lower `WOW_HOURLY_RETENTION_DAYS` in `/etc/ludeal/fetcher.env`: 7 halves the hourly detail. The fetcher no longer runs when less than 1 GB is free, so that Postgres and the site keep working, and `check.sh` reports it.

## Accounts

Players sign in with Battle.net, with the fetcher's client. For that to work, add the address of the site's callback to the **Redirect URLs** of that client on <https://develop.battle.net/access/clients>. `install.sh` prints it when given a domain:

```text
https://trading.example.com/auth/battlenet/callback
```

With `BASE_PATH`, the path comes before `/auth`. It changes with the domain and the path of the site: after moving it, add the new one. Without this URL, Battle.net refuses to send players back to the site. The whole of the site still works without an account.

What players save is in the `ludeal_accounts` database. Nothing there can be fetched again: see [Backups](#backups).

### Alerts by email

The site only offers alerts once it can send emails. Uncomment and fill in `SMTP_ADDRESS` and the lines under it in `/etc/ludeal/site.env`, with the details your email provider gives, then run `sudo ./deploy/install.sh` again. That starts `ludeal-alerts.timer`, which looks for products that reached their target 2 minutes after each cycle of the fetcher. Check how your provider limits sending: each player gets at most one email per run.

## Day to day

| To | Command |
| --- | --- |
| Know if all is well | `sudo ./deploy/check.sh` |
| Read the fetcher's logs | `journalctl -u ludeal-wow-fetcher.service -f` |
| Read the site's logs | `journalctl -u ludeal-site.service -f` |
| Run a cycle right now | `sudo systemctl start --no-block ludeal-wow-fetcher.service` |
| Pause the fetcher | `sudo systemctl stop ludeal-wow-fetcher.timer` |
| Update | `git pull && sudo ./deploy/install.sh` |
| Follow other markets | Change `WOW_SCOPE` in `/etc/ludeal/fetcher.env`, taken into account at the next cycle |
| Read the alerts' logs | `journalctl -u ludeal-alerts.service -f` |
| Back up right now | `sudo systemctl start ludeal-backup.service` |

### Backups

Each night at 03:40 UTC, `ludeal-backup.timer` saves what cannot be fetched again in `/var/backups/ludeal`. `install.sh` also takes one before each update.

- `accounts-<day>.dump`: the whole of the accounts database. It is small, and 14 days of it are kept, to go back to before a mistake.
- `market-<day>.dump`: the market data without the hourly detail of the last days, nor what the fetcher works out again at its next snapshot. That leaves the names of items, realms and markets, the log of snapshots and the daily history. It starts at about a megabyte, then grows with each day of history, which is never purged. Each copy holds the whole of that history, so only the two latest are kept. Restored, it loses at most the hours not yet rolled up into days, `WOW_HOURLY_RETENTION_DAYS` at worst.

**These copies are on the server's own disk.** They protect from a mistake, not from losing the server: copy them elsewhere as well, or take Scaleway snapshots of the volume. `check.sh` says how old and how big the latest are.

To restore, with the services stopped so that nothing is connected meanwhile. Each command replaces a whole database, with its owner and settings, by the one in the file:

```sh
sudo systemctl stop ludeal-site.service ludeal-wow-fetcher.timer ludeal-wow-fetcher.service ludeal-alerts.timer ludeal-alerts.service
sudo -u postgres pg_restore --clean --if-exists --create -d postgres /var/backups/ludeal/accounts-<day>.dump
sudo -u postgres pg_restore --clean --if-exists --create -d postgres /var/backups/ludeal/market-<day>.dump
sudo ./deploy/install.sh
```

Without `--create`, restoring over the market data fails on its daily partitions.

The fetcher fills in the latest snapshot at its next cycle, so curves and listings come back within the hour.

### Updating an install from before a rename

The project used to be called wow-market, then wow-trading. On a server installed under one of those names, `install.sh` renames the install before updating it: the services, the system user, the directories in `/opt`, `/etc` and `/var/backups`, the databases and their roles. The history, the accounts and the credentials are kept. A `git pull` still works, as GitHub redirects the old address.

It stops the old services first, so the site is down for the length of the update, and longer the first time: the fetcher has a new name too, and is compiled again.

The old install's `DOMAIN` and `BASE_PATH` are kept as well. To move the site while renaming it, pass the new ones, with the old domain as [`WOW_DOMAIN`](#a-domain-the-world-of-warcraft-pages-had-to-themselves) if it had one.

A backup taken before the rename restores its database under the name it had then. Rename it before running `install.sh`, for example with `ALTER DATABASE wow_trading RENAME TO ludeal_wow`, and `wow_trading_accounts` to `ludeal_accounts`.

Item names already stored stay in the language they were fetched in, and an existing `fetcher.env` keeps its `WOW_LOCALE`. To change language, set `WOW_LOCALE` in `/etc/ludeal/fetcher.env`, then forget the stored names:

```sh
sudo -u postgres psql -d ludeal_wow -c "UPDATE items SET name = NULL, resolved_at = NULL; UPDATE pets SET name = NULL, resolved_at = NULL;"
```

The fetcher looks them up again at 1,000 per cycle, which takes about 2 hours for 25,000 items. Until then they show as `Item #…`.

## What the script creates

| What | Where |
| --- | --- |
| Programs | `/opt/ludeal` |
| Credentials and settings, readable by root and `ludeal` only | `/etc/ludeal/fetcher.env`, `/etc/ludeal/site.env` |
| System user | `ludeal` |
| Postgres databases and roles | `ludeal_wow`, `ludeal` (owner, for the fetcher), `ludeal_site` (read only there, for the site); `ludeal_accounts`, owned by `ludeal_site` |
| systemd units | `ludeal-wow-fetcher.service`, `ludeal-wow-fetcher.timer`, `ludeal-site.service`, `ludeal-alerts.service`, `ludeal-alerts.timer`, `ludeal-backup.service`, `ludeal-backup.timer` |
| Backups, readable by `postgres` only | `/var/backups/ludeal` |
| With a domain | `/etc/caddy/Caddyfile`, the previous one being kept as `Caddyfile.before-ludeal` |
