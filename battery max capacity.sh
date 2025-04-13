#!/bin/bash

batteryMaxCapacity=$(system_profiler SPPowerDataType | grep "Maximum Capacity:" | sed 's/.*Maximum Capacity: //')
echo "<result>$batteryMaxCapacity</result>"