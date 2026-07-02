#!/bin/bash

# EA: Connected Bluetooth Devices
# Returns a newline-separated list of connected Bluetooth peripheral names.
# Result Type: String

connected_devices=$(
    system_profiler SPBluetoothDataType -json 2>/dev/null \
    | jq -r '
        .SPBluetoothDataType[].device_connected[]?
        | to_entries[]
        | .key
    ' 2>/dev/null
)

if [[ -z "$connected_devices" ]]; then
    echo "<result>None</result>"
else
    echo "<result>$connected_devices</result>"
fi