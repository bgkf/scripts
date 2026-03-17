#!/bin/bash
# =============================================================================
# glassworm_cleanup_ea.sh
# Jamf Pro Extension Attribute
#
# Reads the result file written by uninstall_extensions.sh and returns it
# as the EA value. Jamf captures the last line of stdout as the EA result.
#
# EA Configuration in Jamf Pro:
#   Name        : Glassworm v2 Cleanup Results
#   Description : Reports blocked extension matches found by the cleanup script
#   Data Type   : String
#   Input Type  : Script
#
# Possible values returned:
#   "0 matches"
#   "3 matches: ext.one, ext.two, ext.three"
#   "not run"    -- script has never executed on this machine
# =============================================================================

EA_FILE="/opt/glassworm-cleanup-ea.txt"

if [[ -f "$EA_FILE" ]]; then
    result=$(cat "$EA_FILE")
    # Ensure the value is a single non-empty line
    if [[ -n "$result" ]]; then
        echo "<result>${result}</result>"
    else
        echo "<result>not run</result>"
    fi
else
    echo "<result>not run</result>"
fi
