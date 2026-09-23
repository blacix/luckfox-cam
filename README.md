# LuckFox Pico Mini IMX415 Camera Support

This repository contains the work required to add Sony IMX415 camera support
to a LuckFox Pico Mini board based on the Rockchip RV1103G SoC.

The project covers the kernel sensor driver, device-tree configuration,
Rockchip camera-pipeline integration, firmware changes, camera tuning files,
and the validation needed to capture frames from the board.

## Target hardware

- Board: LuckFox Pico Mini
- SoC: Rockchip RV1103G
- Kernel: Linux 5.10.160
- Operating system: Buildroot 2023.02.6
- Camera: Sony IMX415
- Camera interface: two-lane MIPI CSI-2

The RV1103 camera pipeline is limited compared with the native IMX415
resolution. Development should therefore begin with a supported reduced
resolution or high-frame-rate mode before attempting the native 3840 x 2160
mode.

## Repository structure

```text
.
├── README.md
├── camera.md
├── implementation-plan.md
└── sdk/                         # Local SDK and firmware tools; ignored by Git
    ├── Luckfox_Pico_Mini_Flash_250607/
    │   └── Stock firmware images and update files
    ├── luckfox-pico/
    │   └── LuckFox Pico SDK source tree
    └── upgrade_tool_v2_17/
        └── Firmware upgrade utility and supporting files
```

### Documentation

- `camera.md` records the current board state, camera pipeline findings,
  installed drivers, firmware contents, and hardware compatibility questions.
- `implementation-plan.md` defines the staged plan for building, integrating,
  flashing, and validating IMX415 support.

### `sdk/`

The `sdk/` directory is a local working area for the large files needed to
build and flash the board. It currently contains:

- the LuckFox Pico SDK source tree;
- the stock LuckFox Pico Mini firmware image set used for rollback and
  comparison;
- the LuckFox firmware upgrade tool.

The directory is intentionally ignored in the root `.gitignore` because it is
large and contains vendor tools and firmware artifacts. A fresh checkout must
therefore be supplied with the required SDK and firmware files separately.

### Flashing the stock image

The stock firmware image is located at:

```text
sdk/Luckfox_Pico_Mini_Flash_250607/update.img
```

`upgrade_tool` is included locally and is not installed on `PATH`. Run the
command from the directory containing the tool and `update.img`:

```sh
upgrade_tool uf update.img
```

For example:

```sh
./sdk/upgrade_tool_v2_17/upgrade_tool uf \
  ./sdk/Luckfox_Pico_Mini_Flash_250607/update.img
```

The board should be recoverable to this stock image before experimental
firmware changes are flashed.

## Development objective

The first practical milestone is:

> A rebuilt firmware image boots, the IMX415 reports its correct sensor ID,
> and a reduced two-lane mode produces frames through the RKCIF/V4L2 path.

Work should proceed in this order:

1. Preserve and verify the stock firmware recovery path.
2. Confirm the exact IMX415 module, wiring, I²C address, clock, power rails,
   and GPIO configuration.
3. Build an unchanged SDK baseline for the target board.
4. Enable and package the IMX415 kernel driver.
5. Replace the SC3336 device-tree configuration with a verified IMX415 node.
6. Validate sensor probing, media links, and conservative capture modes.
7. Add and validate an appropriate IMX415 IQ/tuning configuration.
8. Integrate and test the complete application camera path.

The stock SC3336 IQ file must not be treated as an IMX415 configuration.

## Building the IMX415 kernel module

The local LuckFox SDK already contains the IMX415 driver and enables it as a
loadable kernel module with `CONFIG_VIDEO_IMX415=m`.

The tracked root-level DTSI is the source of truth for local camera changes:

```text
rv1103-luckfox-pico-ipc.dtsi
```

Select the LuckFox Pico Mini configuration once using the SDK menu:

```sh
./sdk/luckfox-pico/build.sh lunch
```

Select these options from the menus:

```text
RV1103_Luckfox_Pico_Mini
SPI_NAND
Buildroot
```

After selecting the board, return to the repository root. Build the complete
SDK image set and package a flashable `update.img`:

```sh
./build-camera.sh
```

The script copies `rv1103-luckfox-pico-ipc.dtsi` into the SDK, runs
`sdk/luckfox-pico/build.sh all`, and runs `updateimg`.

After the build, locate the generated module and verify the kernel
configuration:

```sh
ls -l sdk/luckfox-pico/sysdrv/source/objs_kernel/drv_ko/lib/modules/5.10.160/kernel/drivers/media/i2c/imx415.ko
grep -n "CONFIG_VIDEO_IMX415" sdk/luckfox-pico/sysdrv/source/objs_kernel/.config
```

The expected configuration is:

```text
CONFIG_VIDEO_IMX415=m
```

## Temporarily loading the module on the device

From the host shell, copy the module to a temporary directory on the
board, then open an interactive shell on the device:

```sh
adb push sdk/luckfox-pico/sysdrv/source/objs_kernel/drv_ko/lib/modules/5.10.160/kernel/drivers/media/i2c/imx415.ko /tmp/imx415.ko
adb shell
```

The following commands are issued from the device shell after running
`adb shell`:

```sh
uname -r
id
ls -l /tmp/imx415.ko
insmod /tmp/imx415.ko
lsmod | grep imx415
dmesg | tail -n 80
```

If the device shell is not running as root, exit the shell and restart ADB as
root from the host shell before entering it again:

```sh
adb root
adb shell
```

Then repeat the device-shell commands above.

This temporary test does not modify the firmware image. It verifies module
compatibility with the running kernel, but it will not probe the camera yet
because the running device tree still describes the SC3336 sensor. A successful
module load may therefore produce no IMX415 sensor messages.

If loading fails, capture the complete error and recent kernel log. Common
failures include an invalid module format, an ARM architecture mismatch,
missing symbols, or insufficient permissions.

## Starting device-tree integration

The tracked root-level DTSI is the file to edit. Create a backup before
changing it:

```sh
cp rv1103-luckfox-pico-ipc.dtsi rv1103-luckfox-pico-ipc.dtsi.orig
```

The build script copies this file to the SDK path selected by the board DTS.
The SC3336 sensor nodes and CSI endpoint connections are defined in it.
Inspect them from the repository root:

```sh
grep -n -E "sc3336|sc4336|sc530ai|mipi|csi2|endpoint|ff470000" \
  rv1103-luckfox-pico-ipc.dtsi
```

Replace the SC3336 sensor node with an IMX415 sensor node in the included
DTSI file. Also update the corresponding CSI endpoint reference from
`sc3336_out` to the new IMX415 endpoint name. Preserve the
existing CSI-2, RKCIF, and endpoint graph unless the board wiring requires a
change. The IMX415 node must use the confirmed sensor I²C address, clock,
regulators, GPIOs, and two-lane CSI-2 configuration; do not guess unverified
hardware properties.

After editing the device tree, rebuild and package from the repository root:

```sh
./build-camera.sh
```

The updated device tree must eventually be packaged into the boot image. The
kernel module and device-tree changes are both required for the IMX415 driver
to bind to the sensor.

Building the module alone does not configure the camera. The current firmware
still contains an SC3336 device-tree node, so IMX415 support will also require
an IMX415 device-tree node and packaging the resulting module and device tree
into the firmware image. Do not flash the board until the module, device tree,
and recovery image have been checked together.

## Current device-tree integration

The tracked root DTSI currently contains the staged camera migration:

- SC3336, SC4336, and SC530AI nodes are disabled.
- The CSI-2 input endpoint points to `imx415_out`.
- The IMX415 node is enabled at I²C address `0x30`.
- The existing MIPI clock and camera power-down pin are reused.
- Reset GPIO and regulator assignments remain TODOs until the module wiring is
  confirmed.

The root-level build script is the required build entry point:

```sh
./build-camera.sh
```

After a successful build, the complete firmware image is available at:

```text
sdk/luckfox-pico/output/image/update.img
```

Flash it from the repository root with the local upgrade tool:

```sh
./sdk/upgrade_tool_v2_17/upgrade_tool uf \
  ./sdk/luckfox-pico/output/image/update.img
```

## Status

The supplied board image currently contains SC3336 support and does not
contain an installed `imx415.ko` module or IMX415 IQ file. The LuckFox SDK
contains an IMX415 driver implementation and is the starting point for the
kernel and device-tree integration work.

See [camera.md](camera.md) and [implementation-plan.md](implementation-plan.md)
for the detailed findings and plan.
