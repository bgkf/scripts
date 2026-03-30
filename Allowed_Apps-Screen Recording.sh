#!/bin/bash

# Jamf extension attribute
# Checks system + per-user TCC databases for kTCCServiceScreenCapture grants.

SERVICE="kTCCServiceScreenCapture"
SYSTEM_TCC="/Library/Application Support/com.apple.TCC/TCC.db"
RESULTS=()

query_tcc() {
    local db="$1"
    if [[ -f "$db" ]]; then
        sqlite3 "$db" \
            "SELECT client FROM access \
             WHERE service = '$SERVICE' \
             AND auth_value = 2 \
             ORDER BY client;" 2>/dev/null
    fi
}

# System-level TCC
while IFS= read -r line; do
    [[ -n "$line" ]] && RESULTS+=("$line")
done < <(query_tcc "$SYSTEM_TCC")

# Per-user TCC databases
for USER_HOME in /Users/*; do
    USER_TCC="$USER_HOME/Library/Application Support/com.apple.TCC/TCC.db"
    while IFS= read -r line; do
        [[ -n "$line" ]] && RESULTS+=("$line")
    done < <(query_tcc "$USER_TCC")
done

# Deduplicate and sort
UNIQUE=$(printf '%s\n' "${RESULTS[@]}" | sort -u)

if [[ -z "$UNIQUE" ]]; then
    echo "<results>None</results>"
else
    echo "<results>"
    echo "$UNIQUE"
    echo "</results>"
fi
