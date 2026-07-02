#!/bin/bash

# EA: Connected USB Devices
# Returns a newline-separated list of connected USB devices with vendor and product name.
# Result Type: String

connected_devices=$(
    ioreg -r -c IOUSBHostDevice -l \
    | awk '
        /"USB Vendor Name" =|"kUSBVendorString" =/ {
            if (vendor == "") {
                line = $0
                sub(/.*"USB Vendor Name" = "/, "", line)
                sub(/.*"kUSBVendorString" = "/, "", line)
                sub(/".*/, "", line)
                vendor = line
            }
        }
        /"USB Product Name" =/ {
            line = $0
            sub(/.*"USB Product Name" = "/, "", line)
            sub(/".*/, "", line)
            product = line
            if (vendor != "" && product != "") {
                print vendor " — " product
            }
            vendor = ""
        }
        /\+-o / {
            vendor = ""
        }
    ' \
    | grep -v -E 'USB[0-9. ]+Hub|BILLBOARD|Billboard|Generic|VIA Labs|VLI Inc' \
    | sort -u
)

if [[ -z "$connected_devices" ]]; then
    echo "<result>None</result>"
else
    echo "<result>$connected_devices</result>"
fi