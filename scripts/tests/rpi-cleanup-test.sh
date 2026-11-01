#!/usr/bin/env bash
# Isolated cleanup tests: no real sudo, apt, GPIO, or battery access.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
bash -n "$repo/scripts/rpi-setup.sh"
bash -n "$repo/scripts/rpi-cleanup.sh"
[[ $EUID != 0 ]] || { echo 'Run tests as a normal user.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"
mkdir -p "$HOME" "$work/bin"
export TEST_LOG="$work/commands" TEST_REMOVED="$work/removed"
export PATH="$work/bin:$PATH"
cat >"$work/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_LOG"
if [[ $* == 'apt-get remove '* && ${TEST_CANCEL:-0} != 1 ]]; then
  touch "$TEST_REMOVED"
fi
EOF
cat >"$work/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
if [[ -e "$TEST_REMOVED" ]]; then
  printf 'deinstall ok config-files'
else
  printf 'install ok installed'
fi
EOF
chmod +x "$work/bin/sudo" "$work/bin/dpkg-query"
state="$HOME/.local/state/dyson-v15-rpi"
fixture() {
  mkdir -p "$state/build"
  printf 'dyson-v15-rpi-v1\n' >"$state/marker"
  printf 'new-tool\n' >"$state/installed-packages.txt"
  printf 'cmake\n' >"$state/auto-before.txt"
  printf 'cmake\n' >"$state/requested-packages.txt"
  : >"$TEST_LOG"
}
fixture
printf 'y\ny\n' | bash "$repo/scripts/rpi-cleanup.sh" >/dev/null
[[ ! -e "$state" && ! -s "$TEST_LOG" ]]
fixture
printf 'y\n' | bash "$repo/scripts/rpi-cleanup.sh" --remove-packages >/dev/null
[[ ! -e "$state" ]]
grep -Fxq 'apt-get --simulate remove --no-auto-remove new-tool' "$TEST_LOG"
grep -Fxq 'apt-get remove --no-auto-remove new-tool' "$TEST_LOG"
grep -Fxq 'apt-mark auto cmake' "$TEST_LOG"
rm -- "$TEST_REMOVED"
fixture
export TEST_CANCEL=1
if bash "$repo/scripts/rpi-cleanup.sh" --remove-packages </dev/null >/dev/null 2>&1; then
  echo 'Expected cancelled apt removal to retain state.' >&2; exit 1
fi
[[ -d "$state" ]]
unset TEST_CANCEL
printf '%s\n' '--dangerous-option' >"$state/installed-packages.txt"
if bash "$repo/scripts/rpi-cleanup.sh" --remove-packages </dev/null >/dev/null 2>&1; then
  echo 'Expected invalid recorded package rejection.' >&2; exit 1
fi
[[ -d "$state" ]]
printf 'wrong-marker\n' >"$state/marker"
if bash "$repo/scripts/rpi-cleanup.sh" </dev/null >/dev/null 2>&1; then
  echo 'Expected invalid marker rejection.' >&2; exit 1
fi
[[ -d "$state" ]]
echo 'PASS: syntax, scoped cleanup, package removal, cancellation, and state validation.'
