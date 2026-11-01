# Raspberry Pi setup and recovery plan for a Dyson V15 pack

This plan builds this repository's replacement BMS firmware and prepares a Pi
as an SWD programmer. Firmware replacement may address a software lockout; it
cannot repair failed cells, a blown fuse, or damaged FETs. Direct Pi GPIO use is
experimental and has not been hardware-validated for this repository.

## 1. Identify the pack and prepare the workspace

- Confirm **ATSAMD20E15**, **BQ7693003**, and **7S** on the actual board. A V15
  label alone does not establish compatibility. Stop if the components differ.
- Do not work on a swollen, leaking, damaged, or unusually hot battery. Do not
  bypass its protection circuits or force-charge cells. If you cannot safely
  identify exposed pads, use a qualified battery repair service.
- Use a Raspberry Pi **3 Model B/B+ or 4 Model B**, its normal power supply,
  Raspberry Pi OS, Internet access, and four short insulated jumper leads
  (aim for 10 cm or less). The scripts reject other Pi models before changes.
- Disconnect the pack from the vacuum and charger. Work on a nonconductive
  surface with insulated tools. Pack pads remain live even with the Pi off.

## 2. Install Raspberry Pi OS and copy this repository

Use Raspberry Pi Imager to install Raspberry Pi OS. Set a username, password,
network access, and optionally SSH in Imager. Boot and log in as that normal
user. Confirm the model with `cat /proc/device-tree/model`.

Copy this checkout to `~/V11_Dyson_BMS` (for example with SCP from your computer).
No old V10 autoflash image is needed. Keep this checkout until cleanup is done.
Run all following shell commands on the Pi, not Windows:

```bash
cd ~/V11_Dyson_BMS
bash scripts/rpi-setup.sh
```

The script asks for sudo only for APT. It installs build tools and OpenOCD,
checks the GPIO driver, creates a model-specific configuration, and builds
Release firmware. It requires V15's `TRIGGER_TOGGLE_MODE=0`, without editing
source. It creates no boot services, GPIO overlays, UART changes, or autostart.

All generated files and package tracking are under
`~/.local/state/dyson-v15-rpi/`. Setup refuses an existing state directory;
after a failure, inspect the error, run cleanup, then retry. Do not run other
package installations during setup, since package tracking uses before/after
snapshots. CMake must be 3.20+; use an up-to-date OS if configuration rejects it.

## 3. Connect four cables

Shut down the Pi (`sudo poweroff`) and disconnect its power before attaching
leads. Locate pads using [the board-header image](flashing-header-pinout.png)
and verify orientation against your PCB. Identify pin 1 on the Pi header;
physical pin numbers and BCM GPIO numbers are different.

| Pi physical pin (40-pin header) | BCM signal | Battery board pad |
|---|---|---|
| 20 | Ground | GND |
| 23 | GPIO11 | SWCLK |
| 24 | GPIO8 | SWDIO |
| 18 | GPIO24 | RST |

Connect ground first, then signals. Insulate all joints and inspect for bridges.
**Leave the battery's 3.3 V pad unconnected. Never attach either Pi power rail
(3.3 V or 5 V) to the pack.** The pack powers its MCU; the Pi supplies only
3.3 V logic signals. This generated configuration explicitly sets SWDIO to
GPIO8; older Internet instructions often use GPIO25/physical pin 22 instead.
Do not combine those mappings. Do not enable SPI on these GPIOs or share them
with a HAT/peripheral during programming.

## 4. Test the connection without erasing or flashing

Power the Pi, log in, and prepare this command. Press the pack's trigger to wake
its MCU immediately before running it:

```bash
TASK_DIR="$HOME/.local/state/dyson-v15-rpi"
sudo openocd -f "$TASK_DIR/openocd-v15.cfg" -c 'init; shutdown'
```

This initializes the SWD connection without an erase/program command. Look for
a detected debug port/target rather than assuming that OpenOCD starting means
success. Protection may limit target examination. For errors, check pad
orientation, common ground, the wake trigger, and cable length; do not erase
as a connection troubleshooting shortcut. The initial clock is approximately
100 kHz; GPIO bit-banging timing depends on the Pi CPU.

## 5. Manual decision: erase and replace firmware

Proceed only with a confirmed compatible, electrically sound pack and a working
SWD connection. **Unlocking permanently erases the original protected firmware;
it cannot first be backed up over SWD. Cleanup cannot undo this.** Review
[the main flashing instructions](../README.md#flashing) before continuing.

Verify both build outputs exist before unlocking:

```bash
test -s "$TASK_DIR/build/samd20_firmware.elf" && \
test -s "$TASK_DIR/build/samd20_firmware.hex"
```

For a protected original board only, the following explicitly performs the
repository's SAMD20 unlock/erase sequence. Wake the pack before each connection:

```bash
sudo openocd -f "$TASK_DIR/openocd-v15.cfg" \
  -c 'init; samd20.cpu mwb 0x41002100 0x10; sleep 500; reset; halt; shutdown'
```

After a successful unlock, program and verify the replacement before disconnecting:

```bash
cd "$TASK_DIR"
sudo openocd -f openocd-v15.cfg \
  -c 'program build/samd20_firmware.elf verify reset exit'
```

Check for successful verification. Do not use `make flash` or `make unlock` for
Pi wiring: the repository defaults select J-Link. On a programming failure, keep
the build artifacts, stop, and diagnose the error rather than repeating erases.

## 6. Validate operation

Stop OpenOCD, power off the Pi, and disconnect its leads before using the pack.
For diagnostics, use a separate **3.3 V logic USB-UART adapter**, with RX to
board PA10 and GND to GND, leaving its power output disconnected. Follow the
[UART pad identification](../README.md#uart-diagnostics) and use 115200, 8N1.
Confirm seven plausible cell readings, pack voltage approximately equal to their
sum, and no unexpected fault before normal charging or vacuum use. Do not
interpret a successful flash as proof the battery is safe. Temperature limits
are not currently enforced for these packs; do not leave charging unattended.
Follow the README's first-boot/calibration procedure only after these checks.

## 7. Undo the Raspberry Pi setup

Stop OpenOCD, disconnect battery wiring, and run from the checkout as the same
normal user who ran setup:

```bash
cd ~/V11_Dyson_BMS
bash scripts/rpi-cleanup.sh --remove-packages
```

Cleanup previews APT removal and then uses APT's confirmation prompt. Review
the proposed removals, particularly if other software now depends on these
tools. It removes packages recorded as newly installed (including dependencies),
restores automatic status for pre-existing requested packages where applicable,
and asks before removing the build, generated configuration, and tracking.
It does not run broad `autoremove`, purge shared configuration, or delete the
checkout. Cancel to keep tracking and retry later. Run cleanup before deleting
the checkout or installing unrelated software that needs these packages.

To retain installed tools and delete only generated files, omit
`--remove-packages`; this also discards tracking for later package removal.
APT index/cache updates, logs, residual package configuration, OS installation,
SSH settings, and the copied checkout remain. Remove your checkout manually
after cleanup if no longer needed. Neither cleanup mode restores Dyson firmware
or reverses a chip erase. This is scoped cleanup, not a full OS rollback.

## Pi 5 and reference material

Pi 5 uses an RP1 GPIO controller and needs a different OpenOCD driver; these
scripts deliberately do not configure it. Use the repository's documented
ST-Link/J-Link/Atmel-ICE procedure instead, or develop and validate a separate
Pi 5 configuration. Do not use Pi 3/4 peripheral addresses on a Pi 5.

- [OpenOCD GPIO driver documentation](https://openocd.org/doc/html/Debug-Adapter-Configuration.html)
- [Current Pi native driver and timing calibration](https://github.com/openocd-org/openocd/blob/master/tcl/interface/raspberrypi-native.cfg)
- [Current GPIO connector mapping](https://github.com/openocd-org/openocd/blob/master/tcl/interface/raspberrypi-gpio-connector.cfg)
- [Pi 5 driver differences](https://github.com/openocd-org/openocd/blob/master/tcl/interface/raspberrypi5-gpiod.cfg)

The scripts require OpenOCD's modern `adapter gpio` syntax (0.12+). They have
passed Bash syntax checks and isolated cleanup tests (file removal, package
tracking, cancellation, and invalid state rejection). Rerun these without sudo:

```bash
bash scripts/tests/rpi-cleanup-test.sh
```

They have not been tested against physical Pi or battery hardware; review and
validate on your board before any irreversible step.
