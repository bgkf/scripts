#!/bin/zsh
# Checks if iCloud Desktop & Documents Sync is enabled (fail) or not (pass) for the currently logged in user.

# Get the loggedInUser
loggedInUser=$(stat -f%Su /dev/console)

# check for the iCloud dirs
if [[ -d /Users/$loggedInUser/Library/Mobile\ Documents/com~apple~CloudDocs/Documents/ ]]; then
	# get the iCloud account
	iCloudAccount=$(/usr/libexec/PlistBuddy -c "print :Accounts:0:AccountID" /Users/$loggedInUser/Library/Preferences/MobileMeAccounts.plist)
	iCloudStatus="FAIL - Document Sync Present for ${iCloudAccount}"
else
	iCloudStatus="PASS"
fi

echo "<result>$iCloudStatus</result>"

exit 0
