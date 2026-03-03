#! /bin/zsh

# variables
loggedInUser=$(stat -f%Su /dev/console)
uid=$(id -u "$loggedInUser")
IBM_Path="/Library/Management/super/IBM Notifier.app/Contents/MacOS/IBM Notifier"
icon_path="/Users/$loggedInUser/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"

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

# build the app list from /Applications, excluding:
#   - /Applications/Utilities
#   - Apple-signed apps (identifier starts with com.apple)
#   - Jamf-signed apps (TeamIdentifier=483DWKW443)
#   - Xcode (explicit fallback)
appList=()
while IFS= read -r -d '' app; do
  appBaseName="$(basename "$app" .app)"
  codeSignInfo=$(codesign -dv "$app" 2>&1)

  # skip Apple apps (identifier starts with com.apple)
  if echo "$codeSignInfo" | grep -q "Identifier=com.apple"; then
    continue
  fi

  # skip Jamf-signed apps (all share TeamIdentifier 483DWKW443)
  if echo "$codeSignInfo" | grep -q "TeamIdentifier=483DWKW443"; then
    continue
  fi

  # skip Xcode explicitly as a fallback
  if [[ "$appBaseName" == "Xcode" ]]; then
    continue
  fi

  appList+=("$appBaseName")

done < <(find /Applications -maxdepth 1 -name "*.app" -not -path "/Applications/Utilities/*" -print0 | sort -z)

# build the dropdown payload string
dropdownPayload="/list Select Application"
for app in "${appList[@]}"; do
  dropdownPayload="$dropdownPayload\n$app"
done
dropdownPayload="$dropdownPayload /selected 0"

# selection popup
appSelection=$($IBM_Path \
-type popup \
-title "Add Write to Group" \
-subtitle "Select the app from the dropdown menu and click \"Add\"." \
-bar_title "Add Write to Group" \
-accessory_view_type dropdown \
-accessory_view_payload "$dropdownPayload" \
-main_button_label "Add" \
-secondary_button_label "Quit" \
-icon_path $icon_path \
-always_on_top)

# put the result of the button click into a variable. OK = 0. Quit = 2.
button=$?

# map the selection ordinal back to an app name
# appSelection is 1-based, matching the index in appList
if [[ $appSelection -gt 0 ]]; then
  appName="${appList[$appSelection]}.app"
fi

# if the main button was clicked, continue
if [[ $button = 0 ]]; then
  echo "The Add button was clicked."

  # if no app was selected
  if [[ $appSelection = 0 ]]; then
    $IBM_Path \
    -type popup \
    -title "No app was selected." \
    -bar_title "Error" \
    -icon_path $icon_path \
    -always_on_top
    echo "No app selection was made."
    exit 0
  fi

  # check if selected app is installed
  if [ ! -d "/Applications/$appName" ]; then
    $IBM_Path \
    -type popup \
    -title "$appName is not installed." \
    -bar_title "Error" \
    -icon_path $icon_path \
    -always_on_top
    echo "$appName is not installed."
    exit 0
  fi

  # apply permissions and report to log
  echo "$appName was selected."
  chmod -R g+w "/Applications/$appName"
  echo "Group write permissions applied to /Applications/$appName."

else
  echo "Quit was clicked on the selection popup."
  exit 0
fi
