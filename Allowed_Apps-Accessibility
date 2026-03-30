#!/bin/bash

# Jamf extension attribute
# Reads the system-level TCC database for kTCCServiceAccessibility grants.

TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"

if [[ ! -f "$TCC_DB" ]]; then
    echo "<results>TCC database not found</results>"
    exit 0
fi

# Query for allowed Accessibility entries (auth_value = 2 means allowed)
APPS=$(sqlite3 "$TCC_DB" \
    "SELECT client FROM access \
     WHERE service = 'kTCCServiceAccessibility' \
     AND auth_value = 2 \
     ORDER BY client;" 2>/dev/null)

if [[ -z "$APPS" ]]; then
    echo "<results>None</results>"
else
    echo "<results>"
    echo "$APPS"
    echo "</results>"
fi
```
