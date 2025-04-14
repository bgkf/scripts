#! /bin/zsh

# Requires Dockutil: https://github.com/kcrawford/dockutil
# Replace <APPNAME> in line 24 with the name of the app.

# variables
dockutil=/usr/local/bin/dockutil
loggedInUser=$(stat -f%Su /dev/console)
uid=$(id -u "$loggedInUser")
plist="/Users/$loggedInUser/Library/Preferences/com.apple.dock.plist"

# functions
runAsUser() {  
  if [ "$loggedInUser" != "loginwindow" ]; then
    launchctl asuser "$uid" sudo -u "$loggedInUser" "$@"
  else
    echo "No user logged in."
    exitCode=1
    exit $exitCode
  fi
}

# Check if the the app is in the dock. Create temp file if it is.
appNameDock="<APPNAME>"
appInDock=$(runAsUser "${dockutil}" --find ${appNameDock} ${plist} | cut -d ' ' -f 1-3)
appSection=$(runAsUser "${dockutil}" --find ${appNameDock} ${plist} | cut -d ' ' -f 5)
appPosition=$(runAsUser "${dockutil}" --find ${appNameDock} ${plist} | cut -d ' ' -f 8)

echo "appNameDock = $appNameDock"
echo "appInDock = $appInDock"
echo "appSection = $appSection"
echo "appPosition = $appPosition"

if [ "$appInDock" = "$appNameDock was found" ]; then
	touch /opt/BrinkAgentDock.txt
    echo "$appInDock in the dock in $appSection at position $appPosition."
    echo "$appInDock;$appSection;$appPosition" >> /opt/BrinkAgentDock.txt
    runAsUser "${dockutil}" --remove /Applications/$appName
    echo "$appName was removed from the dock"
else
	echo "$appName is NOT in the dock."
fi

exit 0
