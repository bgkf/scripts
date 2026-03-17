### VSX Extensions Report and Remove

The glassworm campaign is back in force, it specifically targets vs code/cursor extensions and can cause quite a bit of damage.
<br>
<br>
This is a mechanism to scan for computers with these VSX extensions and, if found, remove them. <br>
- By default the script executes in dryrun mode and does not remove any extensions. <br>
- The `--apply` flag must be passeed (in policy parameter 4 when using Jamf) to actually remove extensions. <br>
- Two files are created in /opt. LOG_FILE="/opt/glassworm-cleanup.log" and EA_FILE="/opt/glassworm-cleanup-ea.txt" <br>
<br>
The list of extensions is sourced from https://socket.dev/supply-chain-attacks/glassworm-v2. <br>
<br>
The `.sh` files were created with an assist from Claude code.
