#!/bin/bash

# EA: Connected External Displays
# Returns a newline-separated list of external displays with resolution and refresh rate.
# Result Type: String

connected_displays=$(
    system_profiler SPDisplaysDataType -json 2>/dev/null \
    | jq -r '
        .SPDisplaysDataType[]?.spdisplays_ndrvs[]?
        | select(
            (.spdisplays_connection_type // "" | test("internal|built-in|lcd"; "i") | not)
            and
            (._name // "" | test("built-in|retina|liquid retina"; "i") | not)
          )
        | {
            name: ._name,
            resolution: (.spdisplays_resolution // "" | gsub(" @ [0-9]+\\.?[0-9]*Hz"; "")),
            refresh: (
              .spdisplays_refresh_rate
              // (.spdisplays_resolution | capture("@ (?<hz>[0-9]+\\.?[0-9]*Hz)") | .hz)
              // "Unknown Hz"
            )
          }
        | "\(.name) — \(.resolution) @ \(.refresh)"
    ' 2>/dev/null
)

if [[ -z "$connected_displays" ]]; then
    echo "<result>None</result>"
else
    echo "<result>$connected_displays</result>"
fi