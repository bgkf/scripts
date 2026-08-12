#!/bin/zsh

loggedInUser=$(stat -f%Su /dev/console)
uid=$(id -u "$loggedInUser")
IBM_Path="/Library/Management/super/IBM Notifier.app/Contents/MacOS/IBM Notifier"
icon_path="/Users/$loggedInUser/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"
chromeSupport="/Users/$loggedInUser/Library/Application Support/Google/Chrome"

runAsUser() {
  if [[ "$loggedInUser" != "loginwindow" ]]; then
    launchctl asuser "$uid" sudo -u "$loggedInUser" "$@"
  else
    echo "No user logged in."
    exit 1
  fi
}

if [[ "$loggedInUser" == "loginwindow" ]]; then
  echo "No user logged in."
  exit 1
fi

# Detect Chrome profile
if [[ ! -f "$chromeSupport/Local State" ]]; then
  runAsUser "$IBM_Path" \
    -type popup \
    -title "Chrome has not been set up yet. Please open Chrome first." \
    -bar_title "Error" \
    -icon_path "$icon_path" \
    -always_on_top
  echo "Chrome Local State file not found."
  exit 1
fi

lastUsedProfile=$(python3 -c "
import json, sys
try:
    with open('$chromeSupport/Local State') as f:
        print(json.load(f)['profile']['last_used'])
except Exception:
    sys.exit(1)
" 2>/dev/null)

if [[ -z "$lastUsedProfile" ]]; then
  lastUsedProfile="Default"
  echo "Could not parse profile from Local State, falling back to Default."
fi

pathToExtensions="$chromeSupport/$lastUsedProfile/Extensions"
echo "Chrome profile: $lastUsedProfile"
echo "Extensions path: $pathToExtensions"

# Selection popup
extSelection=$(runAsUser "$IBM_Path" \
  -type popup \
  -title "Delete and Reinstall an Extension" \
  -subtitle "Select the extension from the dropdown menu, click \"Delete and Reinstall\" and then confirm in the following popup." \
  -bar_title "Delete and Reinstall an Extension" \
  -accessory_view_type dropdown \
  -accessory_view_payload "/list Select Extension\n1Password\nNudge\nOkta\nZoom /selected 0" \
  -main_button_label "Delete and Reinstall" \
  -secondary_button_label "Quit" \
  -icon_path "$icon_path" \
  -always_on_top)
button=$?

if [[ $button -ne 0 ]]; then
  echo "Quit was clicked on the selection popup."
  exit 0
fi

case $extSelection in
  1) extID="aeblfdkhhhdcdjpifhhbdiojplfjncoa"; extName="1Password" ;;
  2) extID="diaecjfdpohehjhliaephjnpnlmeajfa"; extName="Nudge" ;;
  3) extID="glnpjglilkicbckjpbgcfkogebgllemb"; extName="Okta" ;;
  4) extID="kgjfgplpablkjnlkjmjdecgdpfankdle"; extName="Zoom" ;;
  *)
    runAsUser "$IBM_Path" \
      -type popup \
      -title "No extension was selected." \
      -bar_title "Error" \
      -icon_path "$icon_path" \
      -always_on_top
    echo "No extension selection was made."
    exit 0
    ;;
esac

extPath="$pathToExtensions/$extID"
echo "$loggedInUser selected $extName (ID: $extID)"
echo "Extension path: $extPath"

# Check if the extension is installed
if [[ ! -d "$extPath" ]]; then
  runAsUser "$IBM_Path" \
    -type popup \
    -title "$extName is not installed and cannot be deleted." \
    -bar_title "Error" \
    -icon_path "$icon_path" \
    -always_on_top
  echo "$extName is not installed."
  exit 0
fi

# Confirmation popup
runAsUser "$IBM_Path" \
  -type popup \
  -title "Click OK to delete and reinstall $extName. Chrome will be closed." \
  -bar_title "Confirmation" \
  -main_button_label "OK" \
  -secondary_button_label "Quit" \
  -icon_path "$icon_path" \
  -always_on_top
button=$?

if [[ $button -ne 0 ]]; then
  echo "Quit was clicked on the confirmation popup."
  exit 0
fi

echo "Confirmed: deleting and reinstalling $extName."

# Close Chrome if running
if pgrep "Google Chrome" > /dev/null 2>&1; then
  echo "Closing Google Chrome..."
  runAsUser osascript -e 'tell application "Google Chrome" to quit'
  sleep 3
  # Force kill if it didn't close gracefully
  if pgrep "Google Chrome" > /dev/null 2>&1; then
    pkill -f "Google Chrome"
    sleep 2
  fi
fi

# Remove extension from Chrome's preferences so it doesn't leave a stub
python3 << PYEOF
import json

profile_path = "$chromeSupport/$lastUsedProfile"
ext_id = "$extID"

for prefs_file in ["Preferences", "Secure Preferences"]:
    path = f"{profile_path}/{prefs_file}"
    try:
        with open(path) as f:
            prefs = json.load(f)
        if "extensions" in prefs and "settings" in prefs["extensions"]:
            prefs["extensions"]["settings"].pop(ext_id, None)
        try:
            del prefs["protection"]["macs"]["extensions"]["settings"][ext_id]
        except (KeyError, TypeError):
            pass
        with open(path, "w") as f:
            json.dump(prefs, f)
    except Exception:
        pass
PYEOF

# Delete extension files and local storage
rm -rf "$extPath"
rm -rf "$chromeSupport/$lastUsedProfile/Local Extension Settings/$extID"

if [[ -d "$extPath" ]]; then
  runAsUser "$IBM_Path" \
    -type popup \
    -title "Failed to delete $extName. Please contact IT." \
    -bar_title "Error" \
    -icon_path "$icon_path" \
    -always_on_top
  echo "Failed to delete $extPath."
  exit 1
fi

echo "$extName deleted successfully."

runAsUser "$IBM_Path" \
  -type popup \
  -title "$extName has been removed. Please reopen Chrome — the extension will reinstall automatically." \
  -bar_title "Success" \
  -icon_path "$icon_path" \
  -always_on_top

echo "$extName delete and reinstall complete."
exit 0
