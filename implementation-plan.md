## High-level implementation plan

  The work should proceed in stages, with a hardware and boot-recovery checkpoint before modifying the firmware.

  ### 1. Establish a recoverable baseline

  - Record the currently working firmware images in Luckfox_Pico_Mini_Flash_250607/.
  - Document the upgrade-tool command, USB/ADB connection procedure, and recovery method.
  - Keep the stock images untouched as rollback artifacts.
  - Capture a baseline from the running board:
      - dmesg
      - device-tree camera nodes
      - loaded modules
      - media topology
      - V4L2 formats and links
      - partition layout and firmware versions

  Gate: The board can be restored to the supplied stock image before any camera changes.

  ### 2. Verify the IMX415 hardware module

  Before changing software, identify the exact camera module and confirm:

  - Sensor model and I²C address
  - Two-lane versus four-lane MIPI wiring
  - MIPI lane polarity/order
  - Sensor clock requirement
  - Analog, digital, and I/O voltage rails
  - Reset and power-down GPIOs
  - Whether the module supports a reduced-resolution mode

  This is critical because the SDK driver cannot compensate for incompatible wiring or power sequencing.

  Gate: The module’s electrical and MIPI configuration is compatible with the RV1103 board.

  ### 3. Audit the SDK against the installed firmware

  Use the SDK and supplied binaries to determine:

  - Exact SDK revision and target board configuration
  - Kernel version and configuration
  - Existing imx415.c implementation
  - IMX415 Kconfig/Makefile integration
  - RV1103G device-tree files
  - Existing SC3336 camera node and CSI endpoint
  - Image-build and firmware-packaging scripts
  - Whether kernel modules are packaged in rootfs.img, oem.img, or another image

  The stock binaries should also be inspected where practical to compare their DTB, kernel, modules, and camera configuration with the SDK sources.

  Deliverable: A source-to-image map showing which SDK files produce each firmware component.

  ### 4. Build an unchanged SDK baseline

  Build the SDK without camera modifications and verify that it produces a bootable image for the target board.

  This confirms:

  - The host build environment is complete
  - The selected board target is correct
  - The generated images use the expected partition/layout format
  - The upgrade tool can flash the resulting artifacts

  Gate: A baseline SDK build boots successfully, or the differences between the SDK build and supplied stock firmware are understood.

  ### 5. Integrate the IMX415 kernel driver

  Add or enable the SDK’s IMX415 driver:

  - Enable CONFIG_VIDEO_IMX415
  - Decide whether it should be built-in or a loadable module
  - Resolve any API or kernel-version differences
  - Ensure the resulting imx415.ko, if modular, is included in the target image
  - Add required module loading behavior if necessary

  Initially, the goal should only be reliable sensor probing and V4L2 subdevice registration.

  ### 6. Replace the camera device-tree configuration

  Create the IMX415 camera configuration for the RV1103G target:

  - Replace or disable the SC3336 node
  - Add the IMX415 node with the correct I²C address
  - Configure sensor clock, reset, power-down, and regulators
  - Configure the two CSI-2 data lanes
  - Connect the sensor endpoint to the correct CSI/RKCIF endpoint
  - Preserve the board’s existing CSI, RKCIF, and RKISP topology unless changes are required
  - Set Rockchip camera-module metadata consistently

  The first device-tree iteration should use only confirmed electrical properties. Unverified GPIO or regulator values should not be guessed.

  Gate: Boot logs show a valid IMX415 sensor ID and no probe failure.

  ### 7. Start with a conservative sensor mode

  Do not begin with the native 3840×2160 mode.

  Use the smallest supported two-lane mode that is compatible with the RV1103 pipeline, for example:

  - 1284×720 at high frame rate, or
  - approximately 1944×1097 if supported and stable

  Validate:

  - Pixel format and bit depth
  - Link frequency and pixel rate
  - Two-lane bandwidth
  - Frame timing
  - RKCIF capture
  - Memory usage

  Only attempt higher resolutions after the reduced mode is stable.

  ### 8. Handle IQ/tuning configuration separately

  The supplied image has no IMX415 IQ file, so image-quality tuning is a separate workstream.

  Proceed in this order:

  1. Confirm sensor probing.
  2. Confirm raw or minimally processed frame capture.
  3. Confirm RKISP pipeline operation.
  4. Obtain or create an IMX415 IQ file appropriate to the sensor/module/lens.
  5. Install and validate the IQ configuration.

  An existing SC3336 or unrelated sensor IQ file should not be treated as a final IMX415 configuration.

  ### 9. Package and flash incrementally

  Build and flash the smallest necessary change first:

  1. Kernel/module and device tree
  2. Camera-related userspace or IQ files
  3. Application integration, if required

  After each flash:

  - Boot and collect logs
  - Verify the IMX415 probe
  - Check media topology
  - Test a short capture
  - Confirm ADB and normal system operation

  The upgrade tool should be used only after identifying which image contains the changed component. Avoid reflashing unrelated partitions during early iterations.

  ### 10. Validate the complete camera path

  Validation should cover four levels:

  - Sensor: ID read, register initialization, stream start/stop
  - Kernel/media: subdevice, CSI, RKCIF, RKISP links
  - Capture: supported V4L2 formats and stable frame acquisition
  - Application: expected output resolution, encoding, latency, and long-running stability

  Also monitor RAM pressure because the board has very limited memory.

  ### Expected decision points

  The project may stop or change direction if:

  - The module is four-lane-only.
  - Its power or clock requirements are incompatible with the board.
  - The SDK driver does not support the installed kernel without substantial porting.
  - The RV1103 cannot reliably process the desired mode.
  - No usable IMX415 IQ configuration can be obtained.

  The first practical milestone should be:

  > A rebuilt firmware image boots, the IMX415 reports its correct sensor ID, and a reduced two-lane mode produces frames through the RKCIF/V4L2 path.


