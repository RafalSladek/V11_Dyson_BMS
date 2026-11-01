#!/usr/bin/env bash
# Prepare tools and build firmware; never connect to, erase, or flash a pack.
set -euo pipefail
export LC_ALL=C
die() { printf '%s\n' "$*" >&2; exit 1; }
[[ $# == 0 ]] || die 'Usage: bash scripts/rpi-setup.sh'
[[ $EUID != 0 ]] || die 'Run as your normal Pi user; sudo is requested for apt only.'
[[ -r /proc/device-tree/model ]] || die 'Run on a Raspberry Pi 3 or 4.'
model=$(tr -d '\0' </proc/device-tree/model)
case "$model" in
  'Raspberry Pi 3 '*) base=0x3f000000; offset=31 ;;
  'Raspberry Pi 4 '*) base=0xfe000000; offset=52 ;;
  *) die "Unsupported direct-GPIO model: $model. See doc/raspberry-pi-v15.md." ;;
esac
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
[[ -f "$repo/V11_BMS/CMakeLists.txt" ]] || die 'Cannot find firmware source.'
state="$HOME/.local/state/dyson-v15-rpi"
[[ ! -e "$state" && ! -L "$state" ]] || die "Setup state already exists: $state. Run cleanup before setup again."
mkdir -p -- "$(dirname -- "$state")"
mkdir -m 700 -- "$state"
printf 'dyson-v15-rpi-v1\n' >"$state/marker"
printf '%s\n' "$repo" >"$state/repository.txt"
packages=(build-essential cmake gcc-arm-none-eabi libnewlib-arm-none-eabi openocd)
snapshot() { dpkg-query -W -f='${binary:Package} ${Status}\n' | awk '$3 == "ok" && $4 == "installed" {print $1}' | sort -u; }
snapshot >"$state/packages-before.txt"
apt-mark showauto | sort -u >"$state/auto-before.txt"
printf '%s\n' "${packages[@]}" >"$state/requested-packages.txt"
# Record partial apt installs too, so a failed setup remains cleanable.
record_packages() {
  snapshot >"$state/packages-after.txt"
  comm -13 "$state/packages-before.txt" "$state/packages-after.txt" >"$state/installed-packages.txt"
}
trap record_packages EXIT
sudo apt-get update
sudo apt-get install --no-install-recommends -y "${packages[@]}"
record_packages
trap - EXIT
version=$(openocd --version 2>&1 | sed -n 's/^Open On-Chip Debugger \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' | head -n 1)
[[ -n $version ]] && dpkg --compare-versions "$version" ge 0.12.0 || die 'OpenOCD 0.12.0+ is required; run cleanup and update Raspberry Pi OS.'
openocd -c 'adapter list; shutdown' >"$state/adapters.txt" 2>&1
grep -q bcm2835gpio "$state/adapters.txt" || die 'OpenOCD lacks bcm2835gpio; run cleanup and use a supported probe.'
clock_file=/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
[[ -r "$clock_file" ]] || die 'CPU maximum frequency unavailable; cannot calibrate GPIO timing.'
clock=$(cat "$clock_file")
[[ $clock =~ ^[0-9]+$ ]] || die 'Invalid CPU maximum frequency.'
coeff=$((clock / 4))
cat >"$state/openocd-v15.cfg" <<EOF
# Generated for $model. BCM numbering; physical pins 23/24/18/20.
adapter driver bcm2835gpio
bcm2835gpio peripheral_base $base
bcm2835gpio speed_coeffs $coeff $offset
adapter gpio swclk 11
adapter gpio swdio 8
adapter gpio srst 24
transport select swd
set CHIPNAME samd20
source [find target/at91samdXX.cfg]
adapter speed 100
reset_config srst_only srst_open_drain
bindto 127.0.0.1
EOF
# Preserve source settings, but refuse a toggle-trigger build for this V15 plan.
grep -Eq '^#define[[:space:]]+TRIGGER_TOGGLE_MODE[[:space:]]+0([[:space:]]|$)' \
  "$repo/V11_BMS/src/config.h" || die 'V15 requires TRIGGER_TOGGLE_MODE=0; review config.h.'
cmake -S "$repo/V11_BMS" -B "$state/build" -G 'Unix Makefiles' \
  "-DCMAKE_TOOLCHAIN_FILE=$repo/V11_BMS/cmake/arm-none-eabi.cmake" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$state/build" --parallel 2
test -s "$state/build/samd20_firmware.elf"
test -s "$state/build/samd20_firmware.hex"
printf '\nSetup complete: %s\nNo GPIO connection or programming was attempted.\nRead %s/doc/raspberry-pi-v15.md before connecting.\n' "$state" "$repo"
