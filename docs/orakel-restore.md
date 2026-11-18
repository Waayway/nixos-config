# Orakel on hestia: backups and restore

Production's database and uploads are backed up every hour by restic to the Hetzner Storage
Box, repository `orakel` (`modules/server/hosting/orakel.nix`, module
`modules/server/backup/restic.nix`). Staging is not backed up.

## What a snapshot holds

`restic-orakel.service` (timer `restic-orakel.timer`, hourly, up to 10 minutes late):

1. pings Healthchecks `homelab-orakel-backup` `/start`;
2. copies `/var/lib/orakel/orakel.db` with `sqlite3 .backup` **as user orakel** (a consistent
   copy, safe against the running backend; never a raw file copy) to
   `/var/lib/restic-orakel/sqlite/orakel.db`;
3. `restic backup --host hestia --tag nix --tag orakel` of that copy and
   `/var/lib/orakel/uploads`;
4. forget/prune: 48 hourly, 14 daily, 8 weekly, 12 monthly; `restic check` of 1% of the data;
5. pings Healthchecks with the exit status and the log.

The module's TrueNAS part is per repository and `orakel` has none: hestia needs neither
`truenas.enable` nor a route to TrueNAS, only the Storage Box (SSH on port 23) and 1Password.

Secrets (vault Homelab): `restic-orakel` (`password`: the repository password; **losing it
loses the backups**, keep it only in 1Password), `storagebox-backup` (the Storage Box key),
`healthchecks-orakel-backup` (`url`: `https://hc-ping.com/<ping key>/homelab-orakel-backup`).

## Look at the backups

```sh
sudo restic-orakel snapshots
sudo restic-orakel ls latest | head
sudo systemctl start restic-orakel   # a backup now
journalctl -u restic-orakel -e
```

## Rehearse a restore (runbook S12; no effect on the running site)

```sh
sudo restic-orakel restore latest --target /var/tmp/restore-test
sudo sqlite3 /var/tmp/restore-test/var/lib/restic-orakel/sqlite/orakel.db 'PRAGMA integrity_check;'   # ok
sudo find /var/tmp/restore-test/var/lib/orakel/uploads -type f | wc -l   # ≈ ls /var/lib/orakel/uploads | wc -l
sudo rm -rf /var/tmp/restore-test   # it is production data
```

## Restore production

Decide first whether a restore is right: everything written since the snapshot is lost
(tickets bought, payments confirmed by Mollie's webhook). Note the time of the snapshot and
check Mollie's dashboard for payments after it (runbook §4.7).

```sh
sudo systemctl stop restic-orakel.timer          # no backup run in the middle
sudo restic-orakel snapshots                      # pick <id>
sudo restic-orakel restore <id> --target /var/tmp/orakel-restore
sudo sqlite3 /var/tmp/orakel-restore/var/lib/restic-orakel/sqlite/orakel.db 'PRAGMA integrity_check;'

sudo systemctl stop orakel-frontend orakel-backend
sudo install -d -m 0700 /var/lib/orakel-before-restore-$(date +%F)
sudo mv /var/lib/orakel/orakel.db* /var/lib/orakel/uploads /var/lib/orakel-before-restore-$(date +%F)/
sudo install -o orakel -g orakel -m 0640 \
  /var/tmp/orakel-restore/var/lib/restic-orakel/sqlite/orakel.db /var/lib/orakel/orakel.db
sudo rsync -a --chown=orakel:orakel --chmod=D0750,F0640 \
  /var/tmp/orakel-restore/var/lib/orakel/uploads/ /var/lib/orakel/uploads/
sudo systemctl start orakel-backend orakel-frontend
curl -sS https://hetorakeltheater.nl/api/health  # {"status":"ok"}
sudo systemctl start restic-orakel.timer
sudo rm -rf /var/tmp/orakel-restore
```

The moved-aside directory is the way back; delete it once the site is confirmed good.

## During the cut-over window

Stop the timer at runbook P2 (`sudo systemctl stop restic-orakel.timer`) so no run touches
`/var/lib/orakel` while the database is replaced, and start the first new-line backup by hand
at P11 (`sudo systemctl start restic-orakel`, then `sudo systemctl start
restic-orakel.timer`). The first run on an empty or missing database fails and Healthchecks
reports it; that is expected before the production instance first booted.
