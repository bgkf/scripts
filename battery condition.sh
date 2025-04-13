#!/bin/bash

echo "<result>$(system_profiler SPPowerDataType | grep "Condition:" | sed 's/.*Condition: //')</result>"

exit 0