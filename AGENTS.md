# Repository Guidelines

## Project Structure & Module Organization

This repository contains aftermarket firmware for compatible Dyson battery boards using the ATSAMD20E15 MCU and BQ7693003 frontend. Application code lives in `V11_BMS/src/`, with paired `.c`/`.h` modules for BMS control, ADC, serial protocol, timers, and peripherals. Compile-time options and safety thresholds are in `src/config.h`; peripheral configuration is in `src/config/`. Treat `src/ASF/` as vendor code and avoid unrelated edits there. `doc/` holds protocol captures and the programming-header image. Build and debug configuration lives under `V11_BMS/`; `V11_BMS.atsln` opens the Microchip Studio solution.

## Build, Test, and Development Commands

Install ARM GNU tools, CMake 3.20+, and GNU Make. From `V11_BMS/`, use Linux or WSL:

```bash
cmake -S . -B build-linux -G "Unix Makefiles" "-DCMAKE_TOOLCHAIN_FILE=cmake/arm-none-eabi.cmake" "-DCMAKE_BUILD_TYPE=Release"
cmake --build build-linux --parallel 4
```

These commands generate `samd20_firmware.elf` and `.hex` in `build-linux/`. Alternatively, run `make all BUILD_DIR=build-linux`. For Windows toolchain setup and generator arguments, follow `README.md`. Keep Windows and Linux build directories separate. See `V11_BMS/DEBUG.md` for OpenOCD/GDB debugging.

## Coding Style & Naming Conventions

Use GNU99 C and match the surrounding module's formatting: application code commonly uses two-space indentation and braces on separate lines. Use descriptive `snake_case` function and variable names, uppercase macros, and matching module filenames. Keep private helpers `static` and public declarations in headers. Preserve existing Doxygen comments and license headers. The root `.clang-format` sets `ColumnLimit: 0`; avoid broad formatting changes. Address compiler warnings introduced by your changes.

## Testing Guidelines

No automated test framework or coverage requirement is configured. Build affected configurations and inspect reported firmware size. For behavior changes, document hardware validation: board revision, trigger mode, charger/run transitions, fault recovery, and relevant UART traces. Use `doc/` captures as protocol references. Distinguish compilation success from verified hardware operation.

## Commit & Pull Request Guidelines

History uses short, action-oriented subjects such as `fix BMS fault recovery, SOC, and build compatibility`; prefixes are optional. Keep commits focused. PRs should explain behavior changes, link relevant issues, and report toolchain, configuration, build results, and hardware checks or limitations. Explain changes to protection thresholds explicitly.

## Hardware Safety

Read the README before flashing. `make flash` selects J-Link; use the documented configuration for other probes. Unlocking a protected MCU fully erases the original firmware and is irreversible. Never flash or unlock hardware as a routine build check.
