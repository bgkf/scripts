#!/bin/zsh
# Chrome Profile Identification
# Reports all Chrome profiles, their associated accounts, and which is currently active.

loggedInUser=$(stat -f%Su /dev/console)
chromeDir="/Users/$loggedInUser/Library/Application Support/Google/Chrome"

# Check Chrome installation vs first-launch state
if [[ ! -d "/Applications/Google Chrome.app" ]]; then
    echo "Google Chrome is not installed."
    exit 1
fi

localState="$chromeDir/Local State"

if [[ ! -f "$localState" ]]; then
    echo "Chrome is installed but has never been launched by $loggedInUser. No profile data to report."
    exit 0
fi

jq -r '
    .profile.last_used as $last |
    .profile.info_cache | to_entries |
    if length == 0 then
        "No profiles found in Local State."
    else
        (["PROFILE DIR","DISPLAY NAME","ACCOUNT","ACTIVE"] | @tsv),
        (["-----------------","------------------------","------------------------------------","-------------"] | @tsv),
        (.[] | [
            .key,
            (if .value.gaia_name != "" then .value.gaia_name else .value.name // "" end),
            (if .value.user_name != "" then .value.user_name else "(no account)" end),
            (if .key == $last then "<-- last used" else "" end)
        ] | @tsv)
    end
' "$localState" | column -t -s $'\t'

exit 0