#! /bin/zsh

##########################################################################################################

# 1. Get the installed Adobe CC apps. 					    
# 2. Build a JSON array and store it in a variable.	
# 3. Let the user select which apps to uninstall. 	
# 4. Format the uninstall command.						      
# 5. Uninstall the selected apps.						        														                        

# Link to Adobe's Uninstaller documentation:
# https://helpx.adobe.com/enterprise/using/uninstall-creative-cloud-products.html#uninstall-tool

##########################################################################################################

# variables
adobeUninstaller="/usr/local/bin/adobeUninstaller"
loggedInUser=$(stat -f%Su /dev/console)
IBM_Path="/Library/Management/super/IBM Notifier.app/Contents/MacOS/IBM Notifier"
icon_path="/Users/$loggedInUser/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"

# check if uninstaller is installed
if [ -f /usr/local/bin/AdobeUninstaller ]; then
	echo  "The AdobeUninstaller is installed"
else
	echo  "The AdobeUninstaller is NOT installed. Executing the install policy."
	jamf policy -id 1443
fi

# Initialize empty JSON with applications array
adobeAppsJson='{
	"applications": []
}'

# Process applications from /Applications directory
ls -d /Applications/Adobe*20??/Adobe* 2>/dev/null | while read -r appPath; do
	
	appLongName=$(mdls -name kMDItemDisplayName "$appPath" | sed 's/\"//g' | cut -d "=" -f2 | sed 's/^ //' | cut -d "." -f1)
	baseVersion="$(mdls -name kMDItemVersion "$appPath" | sed 's/^\"/#/' | cut -d "." -f 1 | cut -d '"' -f2).0"
	
	# Extract app name without "Adobe" prefix and year suffix
	# Handle names like "Adobe Media Encoder 2025" -> "Media Encoder"
	appShortName=$(echo "$appLongName" | sed 's/^Adobe //' | sed 's/ 20[0-9][0-9]$//')
	
	# Get sapCode from adobeUninstaller if it exists
	# Parse the whitespace-separated output format
	sapCode=$(/usr/local/bin/adobeUninstaller --list | grep -v -E "^-|^\s*$|^AdobeUninstaller|^Creative|^Name" | \
		awk -v target="$appShortName" -v target_ver="$baseVersion" '
		{
			# Find where the SapCode starts (first all-caps field)
			sapcode_pos = 0
			baseversion_pos = 0
			
			for(i = 1; i <= NF; i++) {
				if($i ~ /^[A-Z]{2,5}$/ && sapcode_pos == 0) {
					sapcode_pos = i
				}
				if($i == target_ver && i > sapcode_pos) {
					baseversion_pos = i
					break
				}
			}
			
			if(sapcode_pos > 0 && baseversion_pos > 0) {
				# Reconstruct the app name from fields 1 to sapcode_pos-1
				name = $1
				for(j = 2; j < sapcode_pos; j++) {
					name = name " " $j
				}
				
				# Check if name and version match
				if(name == target && $baseversion_pos == target_ver) {
					print $sapcode_pos
					exit
				}
			}
		}' | head -1)
	
	# Build the combined json entry
	adobeAppsJson=$(echo "$adobeAppsJson" | jq --arg appLongName "$appLongName" \
		--arg appShortName "$appShortName" \
		--arg sapCode "$sapCode" \
		--arg baseVersion "$baseVersion" \
		--arg filePath "$appPath" \
		'.applications |= . + [{
			"appLongName": $appLongName,
			"appShortName": $appShortName,
			"sapCode": $sapCode,
			"baseVersion": $baseVersion,
			"filePath": $filePath
		}]')
done

echo "$adobeAppsJson"

# construct the checklist payload for the popup. 
checklist=$(echo "$adobeAppsJson" | jq -r '.applications.[] | .appLongName' | sed 's/$/\\n/g' | tr -d '\n' | sed 's/$\\n//')
echo "$checklist"

# popup to select which adobe apps to uninstall
appSelection=($($IBM_Path \
-type popup \
-bar_title "Delete Adobe Creative Cloud Applications" \
-title "Check the box next to each application you want to remove and then confirm in the following popup." \
-accessory_view_type checklist \
-accessory_view_payload "/list $checklist /required" \
-main_button_label "Delete Selected Apps" \
-secondary_button_label "Quit" \
-icon_path $icon_path \
-always_on_top))

# Put the result of the button click into a variable. Ok = 0. Quit = 2.
appSelectionButton=$?
# echo $appSelectionButton
# echo $appSelection

# Main
echo "$loggedInUser Delete Adobe Creative Cloud Applications:"

if [[ $appSelectionButton = 0 ]]; then
	# Report to log: which button was clicked.
	printf '%b\n'
    echo "The OK button was clicked on the app selection pop-up."			
	
	# confirm the apps to delete
	confirm=$(echo $appSelection | sed 's/ /,/g')
	# echo $confirm

	confirming=$(echo $adobeAppsJson | jq -r ".applications.[$confirm] | \"• \(.appLongName)\"")
	echo "The apps selected to delete are: $confirming"

	confirmation=$($IBM_Path \
	-type popup \
	-bar_title "Delete Adobe Creative Cloud Applications" \
	-title "Click the Confirm button to delete the Adobe applications listed below" \
	-subtitle "$confirming" \
	-main_button_label "Confirm" \
	-secondary_button_label "Quit" \
	-icon_path $icon_path \
	-always_on_top)

	# Put the result of the button click into a variable. Ok = 0. Quit = 2.
	confirmationButton=$?
	# echo $confirmation

	# if statement to quit of continue
	if [[ $confirmationButton = 0 ]]; then
	# Report to log: which button was clicked.
		printf '%b\n'
        echo "The OK button was clicked on the confirmation pop-up."

		# create the string of products for the delete command
		products=""
		for index in $appSelection; do
			echo "parsing index: $index"
			product=$(echo $adobeAppsJson | jq -r ".applications.[$index] | \"\(.sapCode)#\(.baseVersion)\"")
			echo $product
		    products+="$product,"
		done

		# echo $products 
		products=$(echo $products | sed 's/,$//')
		echo "The products string is $products"

		# uninstall specified products and versions
		#$adobeUninstaller --products=PHSP\#25.0,PHSP\#26.0,ILST\#28.0,ILST\#29.0,IDSN\#20 --skipNotInstalled
		echo "Deleting the selected apps."
        $adobeUninstaller --products=$products
        
        # could add a check and confirmation for the end user

	else
		# Report to log and exit.
        echo "The Quit button in the confirmation pop-up."
		exit 0			
	fi
else
	# Report to log and exit.
	echo "The Quit button was clicked on the selection popup."
	exit 0
fi
