#!/bin/bash
clamshell=$(system_profiler SPDisplaysDataType | grep Retina)

if [[ "$clamshell" ]]; then
	echo "<result>Online</result>"
else
	echo "<result>Offline</result>"
fi
exit 0