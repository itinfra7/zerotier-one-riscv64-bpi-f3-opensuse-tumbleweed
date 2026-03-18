# zerotier-one-riscv64-bpi-f3-opensuse-tumbleweed

ZeroTier One 1.16.0 installer and release script for Banana Pi BPI-F3 (`riscv64`) on openSUSE Tumbleweed.

## Keywords

Keywords: `#opensuse #suse #tumbleweed #riscv64 #risc-v #bpif3 #bananapi #spacemitk1 #zerotier #tun #vpn #networking`

## Overview

This repository provides a reproducible installation path for ZeroTier One 1.16.0 on Banana Pi BPI-F3 systems running openSUSE Tumbleweed with the vendor kernel `6.1.15-legacy-k1`.

The installer supports both English and `한국어` prompts.

## Technical Design

On this platform the main failure was the vendor kernel configuration, where `CONFIG_TUN` was disabled and Linux could not provide `/dev/net/tun`.

This installer therefore builds and installs ZeroTier One from the pinned upstream source tree, detects missing TUN support on `6.1.15-legacy-k1`, builds `tun.ko` for the running vendor kernel when required, and enables `zerotier-one.service`.

## Target Profile

- Upstream version: ZeroTier One 1.16.0
- Upstream tag commit: `7b7d39becc4a775d33e8c0f673856fb91dea7f31`
- Board: Banana Pi BPI-F3 / SpacemiT K1
- Architecture: `riscv64`
- Operating system: openSUSE Tumbleweed
- Vendor kernel: `6.1.15-legacy-k1`

## Included Files

- `install_zerotier_one_riscv64_bpi_f3_opensuse_tumbleweed.sh` installs build prerequisites, retrieves the pinned upstream ZeroTier source, installs the daemon and systemd unit, detects missing TUN support, builds `tun.ko` for the running vendor kernel when required, and verifies that `zerotier-one.service` is online at the end.

## Quick Start

Open a root shell before running the installer.

The commands below are intended to be run as `root`.

```sh
wget https://github.com/itinfra7/zerotier-one-riscv64-bpi-f3-opensuse-tumbleweed/releases/latest/download/install_zerotier_one_riscv64_bpi_f3_opensuse_tumbleweed.sh
chmod +x install_zerotier_one_riscv64_bpi_f3_opensuse_tumbleweed.sh
./install_zerotier_one_riscv64_bpi_f3_opensuse_tumbleweed.sh
```

## Workflow

1. Check that it is running as `root`.
2. Confirm the machine is an openSUSE environment and record the running kernel release.
3. Install the required build packages with `zypper`.
4. Clone or refresh the upstream ZeroTierOne source tree under `/mnt/sdcard/zerotier/src`.
5. Check out the pinned `1.16.0` commit and build or install ZeroTier.
6. Install `/usr/lib/systemd/system/zerotier-one.service` and start the service.
7. Check whether `/dev/net/tun` is already usable.
8. If TUN is missing, mount the boot partition, reuse the exact vendor kernel config, build `tun.ko`, install it under `/usr/lib/modules/<kernel>/kernel/drivers/net/`, enable automatic loading, and load it immediately.
9. Restart ZeroTier, wait for the local controller socket to become ready, and print final verification output.

## Release Assets

The latest release publishes the following assets:

- `install_zerotier_one_riscv64_bpi_f3_opensuse_tumbleweed.sh`

## Credits

[ZeroTier, Inc.](https://www.zerotier.com/) and the [ZeroTierOne](https://github.com/zerotier/ZeroTierOne) project provide the upstream source code and versioning.

[itinfra7](https://github.com/itinfra7) is credited for the BPI-F3/openSUSE Tumbleweed installation workflow, the TUN analysis, and the installer packaging behind this repository.
