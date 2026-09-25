#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE="${ROOT_DIR}/sdk/luckfox-pico/sysdrv/source/objs_kernel/drv_ko/lib/modules/5.10.160/kernel/drivers/media/i2c/imx415.ko"
LED_TEST="${ROOT_DIR}/test-pwm-led.sh"
REMOTE_MODULE=/tmp/imx415.ko
REMOTE_SCRIPT=/tmp/test-pwm-led.sh
INSTALLED_SCRIPT=/usr/bin/test-pwm-led.sh

if [[ ! -f "${MODULE}" ]]; then
    echo "Missing kernel module: ${MODULE}" >&2
    echo "Build the kernel driver first." >&2
    exit 1
fi

if [[ ! -f "${LED_TEST}" ]]; then
    echo "Missing LED test script: ${LED_TEST}" >&2
    exit 1
fi

adb get-state >/dev/null

echo "Pushing IMX415 kernel module"
adb push "${MODULE}" "${REMOTE_MODULE}"

echo "Pushing LED test script"
adb push "${LED_TEST}" "${REMOTE_SCRIPT}"

echo "Installing LED test script and loading IMX415 module"
adb shell "
    test \"\$(id -u)\" = 0
    chmod 0755 '${REMOTE_SCRIPT}'
    mv '${REMOTE_SCRIPT}' '${INSTALLED_SCRIPT}'
    if ! grep -q '^imx415 ' /proc/modules; then
        insmod '${REMOTE_MODULE}'
    fi
    test -x '${INSTALLED_SCRIPT}'
    grep '^imx415 ' /proc/modules
"

echo "Deployment complete"
echo "Run on the device: ${INSTALLED_SCRIPT}"
