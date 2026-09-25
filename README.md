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

`upgrade_tool` is included locally and is not installed on `PATH`. From the
repository root, run:

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

The tracked kernel configuration is:

```text
luckfox_rv1106_linux_defconfig
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

Before building, the script copies the tracked files into these SDK
destinations:

```text
rv1103-luckfox-pico-ipc.dtsi
  -> sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi
luckfox_rv1106_linux_defconfig
  -> sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig
```

The copied DTSI contains the board-specific hardware description: the IMX415
I²C node and CSI-2 endpoint graph, the disabled legacy camera nodes, the PWM0
pin assignment, the `pwm-leds` consumer for GPIO1_PA2, and the commented-out
ST7789 node that previously used the same pin. The copied defconfig controls
which kernel features are built; in particular, it enables the IMX415 driver
as a module with `CONFIG_VIDEO_IMX415=m` and builds the PWM LED consumer with
`CONFIG_LEDS_PWM=y`.

It then runs `sdk/luckfox-pico/build.sh all` and packages the result with
`updateimg`.

After the build, locate the generated module and verify the kernel
configuration:

```sh
ls -l sdk/luckfox-pico/sysdrv/source/objs_kernel/drv_ko/lib/modules/5.10.160/kernel/drivers/media/i2c/imx415.ko
grep -n "CONFIG_VIDEO_IMX415" sdk/luckfox-pico/sysdrv/source/objs_kernel/.config
```

The expected configuration is:

```text
CONFIG_VIDEO_IMX415=m
CONFIG_LEDS_PWM=y
```

## Deploying the driver and LED test script

After building the kernel module, deploy it and the device-only LED test
script from the repository root:

```sh
./deploy.sh
```

The script pushes `imx415.ko` to `/tmp/imx415.ko`, installs
`test-pwm-led.sh` as `/usr/bin/test-pwm-led.sh`, installs the init script
`S99a-eye` as `/etc/init.d/S99a-eye`, and stores `imx415.ko` in the persistent
`/oem/usr/ko/` module directory. It then restarts `S99a-eye`, which loads the
module with `insmod` if it is not already loaded and starts the LED test
script. The `S99` prefix includes the script in the device's normal init-script
sequence. Deployment requires a connected device with a root ADB shell.

## Testing PWM0 on the second LED

PWM0 uses GPIO1_PA2, which is connected to the second board LED. The ST7789
display node is commented out in the tracked DTSI because it previously used
the same pin as its D/C GPIO.

The device tree enables PWM0, assigns GPIO1_PA2 to it, and declares the LED as
a `pwm-leds` consumer. The consumer owns PWM0 and sets the board's required
`normal` polarity in the device tree. Use the LED class interface rather than
exporting the PWM channel manually.

After booting firmware built from the tracked DTSI, open a root shell on the
device:

```sh
adb shell
```

Verify the PWM device-tree node and LED class device:

```sh
cat /proc/device-tree/pwm@ff350000/status
ls -l /sys/class/leds
```

The device-tree status should report `okay`, and `/sys/class/leds` should
contain `pwm0_led`. Run the device-only test script from the device shell:

```sh
/usr/bin/test-pwm-led.sh
```

The script continuously cycles the LED and turns it off when interrupted.
Because the LED consumer owns PWM0, do not export `pwm0` manually through
`/sys/class/pwm`.

The init script can also be controlled manually from the device shell:

```sh
/etc/init.d/S99a-eye start
/etc/init.d/S99a-eye stop
/etc/init.d/S99a-eye restart
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
compatibility with the running kernel. On firmware built from the current
tracked DTSI, the IMX415 node is enabled and the module may probe the sensor;
on an older stock image, it will only load the module because the device tree
still describes the stock camera configuration.

If loading fails, capture the complete error and recent kernel log. Common
failures include an invalid module format, an ARM architecture mismatch,
missing symbols, or insufficient permissions.

## Starting device-tree integration

The tracked root-level DTSI is the file to edit. Before copying it over the
SDK version, create a backup of the stock SDK DTSI:

```sh
cp sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi \
  sdk/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi.orig
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

Building the module alone does not configure the camera. IMX415 support also
requires the IMX415 device-tree node and packaging the resulting module and
device tree into the firmware image. Do not flash the board until the module,
device tree, and recovery image have been checked together.

## Current device-tree integration

The tracked root DTSI currently contains the staged camera migration:

- SC3336, SC4336, and SC530AI nodes are disabled.
- The CSI-2 input endpoint points to `imx415_out`.
- The IMX415 node is enabled at I²C address `0x30`.
- The existing MIPI clock and camera power-down pin are reused.
- Reset GPIO and regulator assignments remain TODOs until the module wiring is
  confirmed.
- The ST7789 display node is commented out because its D/C signal used
  GPIO1_PA2.
- PWM0 uses GPIO1_PA2 and is exposed through a `pwm-leds` consumer named
  `pwm0_led` with normal polarity.
- The tracked kernel configuration enables both `CONFIG_VIDEO_IMX415=m` and
  `CONFIG_LEDS_PWM=y`.

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

The supplied stock board image currently contains SC3336 support and does not
contain an installed `imx415.ko` module or IMX415 IQ file. The tracked changes
build the IMX415 module and PWM LED support into the development image; IMX415
IQ-file selection and final camera validation remain outstanding.

See [camera.md](camera.md) and [implementation-plan.md](implementation-plan.md)
for the detailed findings and plan.
