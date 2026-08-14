## Desktop App Review

When a request for a new desktop application comes through compliance I generate a report for the decision makers to review. The goal is to understand what gets installed, what permissions the app has and how much technical debt there will be for the IT team to, install, configure and update the app on remote end points. <br>

### Description <br>
Inspect a macOS `.app`, `.dmg`, `.zip`, `.pkg`, or standalone binary for signing, notarization, hardened runtime, entitlements, frameworks, helpers, and Electron fuses. <br>
<br>
Usage: <br>
   app-review.sh <path> [flags] <br>
<br>
 Flags: <br>
   --name <name>         App name (inferred from filename if omitted) <br>
   --txt                 Write review to a .txt file (default) <br>
   --gdoc                Upload to Google Drive via GAM as a Google Doc <br>
   --linear              Create a Linear issue (requires --linear-api-key or LINEAR_API_KEY env) <br>
   --linear-api-key <k>  Linear API key <br>
   --linear-team-id <id> Linear team ID (default: from LINEAR_TEAM_ID env) <br>
   --linear-project <id> Linear project ID (default: from LINEAR_PROJECT_ID env) <br>
   --gam-user <email>    GAM user for Drive upload (default: from GAM_USER env) <br>
   --gdoc-folder-id <id> Google Drive folder ID (default: from GDOC_FOLDER_ID env) <br>
   --source <src>        Installer source: "appstore", "internet", or a URL/description. <br>
                         If omitted, auto-detected from MAS receipt and quarantine xattr. <br>
   --output-dir <dir>    Directory for .txt output (default: current directory) <br>
   -h, --help            Show this help <br>


