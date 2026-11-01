#!/usr/bin/env bash
# Remove setup artifacts, optionally remove packages introduced by setup.
set -euo pipefail
export LC_ALL=C
die() { printf '%s\n' "$*" >&2; exit 1; }
remove_packages=false
case "${1:-}" in
  '') [[ $# == 0 ]] || die 'Unexpected empty argument.' ;;
  --remove-packages) [[ $# == 1 ]] || die 'Unexpected extra arguments.'; remove_packages=true ;;
  *) die 'Usage: bash scripts/rpi-cleanup.sh [--remove-packages]' ;;
esac
[[ $EUID != 0 ]] || die 'Run as the same normal user who ran setup.'
state="$HOME/.local/state/dyson-v15-rpi"
[[ -e "$state" || -L "$state" ]] || { printf 'Nothing to clean up.\n'; exit 0; }
[[ ! -L "$state" && -d "$state" ]] || die 'Refusing a symlink or non-directory state path.'
[[ $(cat "$state/marker") == dyson-v15-rpi-v1 ]] || die 'Unrecognized setup state.'
expected="$(realpath -e -- "$HOME")/.local/state/dyson-v15-rpi"
[[ $(realpath -e -- "$state") == "$expected" ]] || die 'State path resolves outside its expected location.'
if "$remove_packages"; then
  [[ -f "$state/installed-packages.txt" && -f "$state/auto-before.txt" && -f "$state/requested-packages.txt" ]] || die 'Package tracking incomplete; retain state for manual review.'
  packages=()
  while IFS= read -r package; do
    [[ $package =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9]+)?$ ]] || die 'Invalid recorded package name.'
    status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)
    [[ $status != *' ok installed' ]] || packages+=("$package")
  done <"$state/installed-packages.txt"
  if ((${#packages[@]})); then
    printf 'Review this removal simulation. Abort if it removes tools now used elsewhere.\n'
    sudo apt-get --simulate remove --no-auto-remove "${packages[@]}"
    # Keep apt's confirmation prompt; never run broad autoremove or purge.
    sudo apt-get remove --no-auto-remove "${packages[@]}"
    # apt may exit successfully when its user cancels; retain state in that case.
    for package in "${packages[@]}"; do
      status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)
      [[ $status != *' ok installed' ]] || die 'Removal incomplete; keeping setup state. Rerun cleanup to retry.'
    done
  fi
  # apt install can mark an already-installed automatic package as manual.
  while IFS= read -r package; do
    if grep -Fxq "$package" "$state/auto-before.txt"; then
      sudo apt-mark auto "$package"
    fi
  done <"$state/requested-packages.txt"
else
  printf 'Keeping installed tools. Use --remove-packages now for package removal.\n'
  read -r -p 'Delete setup files and package tracking anyway? [y/N] ' answer
  [[ $answer == y || $answer == Y ]] || exit 0
fi
printf 'Ensure OpenOCD is stopped and battery wires are disconnected.\n'
read -r -p 'Remove the setup directory now? [y/N] ' answer
[[ $answer == y || $answer == Y ]] || exit 0
# Only this exact, marker-checked directory is removed, never the checkout.
rm -rf -- "$state"
printf 'Removed %s\nOS, repository, and battery firmware were not reverted.\n' "$state"
