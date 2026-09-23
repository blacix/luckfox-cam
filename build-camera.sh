#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="${ROOT_DIR}/sdk/luckfox-pico"
DTSI_SOURCE="${ROOT_DIR}/rv1103-luckfox-pico-ipc.dtsi"
DTSI_TARGET="${SDK_DIR}/sysdrv/source/kernel/arch/arm/boot/dts/rv1103-luckfox-pico-ipc.dtsi"

if [[ ! -f "${DTSI_SOURCE}" ]]; then
    echo "Missing tracked DTSI: ${DTSI_SOURCE}" >&2
    exit 1
fi

if [[ ! -x "${SDK_DIR}/build.sh" ]]; then
    echo "Missing SDK build script: ${SDK_DIR}/build.sh" >&2
    exit 1
fi

echo "Copying tracked DTSI into the SDK"
cp -- "${DTSI_SOURCE}" "${DTSI_TARGET}"

cd "${SDK_DIR}"

echo "Building the complete SDK image set"
./build.sh all

echo "Packaging update.img"
./build.sh updateimg

echo "Build complete: ${SDK_DIR}/output/image/update.img"
