#!/usr/bin/env bash

set -euo pipefail

run_test() {
    local led=/sys/class/leds/pwm0_led

    if [[ ! -d "$led" ]]; then
        echo "Missing ${led}; boot firmware with the pwm-leds device-tree consumer first." >&2
        exit 1
    fi

    local max
    local low
    local mid
    max=$(cat "$led/max_brightness")
    low=$((max / 4))
    mid=$((max / 2))

    printf "off: %s\n" 0
    echo 0 > "$led/brightness"
    sleep 2

    printf "low: %s\n" "$low"
    echo "$low" > "$led/brightness"
    sleep 2

    printf "mid: %s\n" "$mid"
    echo "$mid" > "$led/brightness"
    sleep 2

    printf "max: %s\n" "$max"
    echo "$max" > "$led/brightness"
    sleep 2
}

run_test
