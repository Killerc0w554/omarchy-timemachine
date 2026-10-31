# Time Machine

An hourglass in the Omarchy bar for btrfs snapshots, built on the snapper
config Omarchy already uses for update recovery.

![hourglass, not a TARDIS](https://img.shields.io/badge/bar-󰔟-8aadf4)

## What it does

- **Left click** opens the panel: snapshot list, dates, descriptions, delete.
- **Right click** takes a snapshot immediately.
- **Middle click** refreshes the list.
- The hourglass flips between empty, half and full while a snapshot is being
  written.

Snapshots are taken with `snapper -c root create`, tagged `important=yes`, and
cover the system subvolume (`@`). `/home` is not included, which is the stock
Omarchy/snapper split.

## Restoring

Snapshots are bootable through `limine-snapper-sync`, which is already enabled
on Omarchy:

1. Take a snapshot (or use a pre-update one) before the change.
2. If the change breaks the system, reboot.
3. Pick the snapshot in the Limine boot menu.
4. Once booted into it, run `omarchy-snapshot restore` in a terminal to make it
   the system subvolume again.

The panel detects when you are running from a snapshot and offers to open that
last step for you.

## One-time setup

The shell runs as your user, so it cannot read `/.snapshots` or call snapper
directly. `setup.sh` installs:

- `/usr/local/bin/omarchy-timemachine` — a root-owned helper that only lists,
  creates, and deletes snapshots (arguments are validated).
- `/etc/sudoers.d/omarchy-timemachine` — passwordless sudo for that exact
  helper, only for your user.

```bash
sudo bash ~/.config/omarchy/plugins/smorg.timemachine/setup.sh
```

The panel shows an **Open setup terminal** button until this is done. Nothing
in snapper's config or the bootloader is modified by the setup.

## Automatic snapshots

A `systemd --user` timer takes a snapshot every day without any clicking.
Scheduled snapshots use the plain `number` cleanup (not `important=yes`), so
they live in the rolling pool alongside Omarchy's pre-update snapshots and
never evict a manual snapshot.

Set it **from the panel** — the popup has an *Automatic snapshots* section with
**Off / 6h / Daily / Weekly** and a live "next run" readout. Or use the script:

```bash
timemachine-schedule status    # show state + next run
timemachine-schedule enable    # enable the daily timer
timemachine-schedule disable   # stop it
timemachine-schedule now       # take one scheduled snapshot right now
timemachine-schedule set 6h    # or: daily / weekly / off
```

Under the hood this is a `~/.config/systemd/user/omarchy-timemachine.timer`
(daily at 09:30 ± 30 min, `Persistent=true`) that runs
`sudo -n /usr/local/bin/omarchy-timemachine schedule`. To set a custom cadence,
edit the timer's `OnCalendar=` and run `systemctl --user daemon-reload`.

## Files

| File | Purpose |
|---|---|
| `manifest.json` | bar-widget plugin declaration |
| `Panel.qml` | bar button + popup |
| `Model.js` | snapshot JSON / date / description helpers |
| `bin/omarchy-timemachine` | root helper source |
| `bin/timemachine-schedule` | scheduler management script |
| `systemd/*.service`, `systemd/*.timer` | reference copies of the user units |
| `setup.sh` | one-time privileged install |

Retention is whatever `/etc/snapper/configs/root` says (Omarchy ships 5 normal
plus 5 important). Use `sudo snapper -c root list` to see everything snapper
knows about.
