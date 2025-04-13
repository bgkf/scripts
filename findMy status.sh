#!/bin/sh

# Determine if FindMyMac is enabled.

fmmToken=$(/usr/sbin/nvram -x -p | /usr/bin/grep "fmm-mobileme-token-FMM")

if [ -z "$fmmToken" ]; then
    /bin/echo "<result>Disabled</result>"
else
    /bin/echo "<result>Enabled</result>"
fi
