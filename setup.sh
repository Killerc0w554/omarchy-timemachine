#!/usr/bin/env bash
# One-time privileged setup for the Time Machine bar widget.
#
# Run it from a terminal:
#   sudo bash ~/.config/omarchy/plugins/smorg.timemachine/setup.sh
#
# It installs a tiny root-owned helper and a sudoers drop-in that lets only
# that helper run without a password. The plugin never edits snapper's own
# configuration or the bootloader.

set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This needs root. Run: sudo bash $0" >&2
  exit 1
fi

src_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
helper_src="$src_dir/bin/omarchy-timemachine"
helper_dst="/usr/local/bin/omarchy-timemachine"
sudoers_dst="/etc/sudoers.d/omarchy-timemachine"

user="${SUDO_USER:-}"
if [[ -z $user || $user == root ]]; then
  echo "Could not tell which desktop user to authorise (SUDO_USER is empty)." >&2
  echo "Run this through 'sudo' as your normal user, not from a root shell." >&2
  exit 1
fi
if [[ ! $user =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Refusing to write a sudoers rule for suspicious user name: $user" >&2
  exit 1
fi

if [[ ! -f /etc/snapper/configs/root ]]; then
  echo "Snapper is not configured for this system." >&2
  echo "Run: sudo bash /usr/share/omarchy/install/config/snapper.sh" >&2
  exit 1
fi

install -o root -g root -m 0755 "$helper_src" "$helper_dst"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s ALL=(root) NOPASSWD: %s\n' "$user" "$helper_dst" >"$tmp"
visudo -cf "$tmp" >/dev/null
install -o root -g root -m 0440 "$tmp" "$sudoers_dst"

echo
echo "Time Machine is ready."
echo "  helper:  $helper_dst"
echo "  sudoers: $sudoers_dst (NOPASSWD for $user)"
echo
echo "Open the hourglass in the bar, or take a snapshot right now:"
echo "  sudo -n $helper_dst list"
