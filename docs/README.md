# Play Deals documentation

| Guide | What it covers |
| --- | --- |
| [README](../README.md) | What the project is, running it on Windows, the fetcher's options |
| [Deployment](../deploy/README.md) | Installing and updating on an Ubuntu server, backups, accounts, alerts |

## Names

The project is **Play Deals**, meant for the domain **playdeals.io**. Until that domain points to the server, the site lives at <https://primo-ideas.xyz/playdeals/>.

| Use | Name |
| --- | --- |
| Shown to readers | Play Deals |
| Repository | `primo-ideas/playdeals-io` |
| Everything on the server (user, directories, databases, services) | `playdeals`, `playdeals_*`, `playdeals-*` |
| Mists of Pandaria Classic markets | `classic-eu`, `classic-us`…, as in Battle.net's namespaces, with `edition = 'classic'` |
| The World of Warcraft fetcher | `playdeals-wow-fetcher` |

It was called wow-market, then wow-trading, then Ludeal. `deploy/install.sh` renames an install from any of them, keeping its history, accounts and credentials: see [Updating an install from before a rename](../deploy/README.md#updating-an-install-from-before-a-rename). The old addresses keep working: `wow-trading.live` and `primo-ideas.xyz/ludeal` redirect to the same page on the site, and GitHub redirects the old repository names.

What the rename does not carry over: the browser session (players sign in again), and the redirect URL of the Battle.net client, to which the new one must be added.
