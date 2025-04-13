#! /bin/zsh

# prompt the end to restart the computer with increasing frequency. 
# uses IBM Notifieer.

# Variables
loggedInUser=$(stat -f%Su /dev/console)
IBM_Path="/Library/Management/super/IBM Notifier.app/Contents/MacOS/IBM Notifier"
icon_path="/Users/$loggedInUser/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"

#check for uptime measures days
units=$(uptime | cut -d, -f1 | awk '{print $4}')
if [ "$units" = "days" ]; then
	days=$(uptime | cut -d, -f1 | awk '{print $3}')
else 
	days=0
fi

# alert function
uptime() {
$IBM_Path \
-type alert \
-title "Restart Recommended - TEST." \
-subtitle "Your laptop has has not restarted in more than 14 days. Please restart your laptop to avoid any future issues that may occur." \
-main_button_label "Close" \
-notification_image $icon_path
}

# notify every 5 days if the number of days since a restart is less than 29.
# notify every 2 days if the number of days since a restart is more than 29.
if (("$days" > 14 && "$days" < 29 && "$days" % 5 == 0)); then
	echo "$days days since last restart. Notification sent."
    uptime
elif (("$days" > 29 && "$days" % 2 == 0)) ; then
	echo "$days days since last restart. Notification sent."
    uptime
else 
	echo "$days days since last restart.
If the days since last restart is less than 29 the notification is sent every 5 days. 
If the days since last restart is greater than 29 the notification is sent every 2 days."
    exit 0
fi

exit 0
