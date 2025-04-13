#! /bin/zsh

# set the variables
Power=$(/usr/libexec/airportd info | grep Power)
SSID=$(/usr/libexec/airportd info | grep SSID | grep -v BSSID | awk '{print $1, $2}')
Security=$(/usr/libexec/airportd info | grep Security)
Channel=$(/usr/libexec/airportd info | grep Channel)
Active=$(/usr/libexec/airportd info | grep Active)
RSSI=$(/usr/libexec/airportd info | grep RSSI)
Noise=$(/usr/libexec/airportd info | grep Noise)
IPv4=$(/usr/libexec/airportd info | grep IPv4)
DNS=$(/usr/libexec/airportd info | grep -C 1 "DNS Address" | awk 'NR >= 2 {print}')
TxRate=$(/usr/libexec/airportd info | grep Tx)

# send the info back to the jamf log 
echo $Power;
echo $Active;
echo $SSID;
echo $Security;
echo $Channel;
echo $IPv4;
echo $DNS;
echo $RSSI;
echo $Noise;
echo $TxRate;

# send the info to the screen
osascript  -e '
display dialog "
'$Power'

'$Active'
Active PHY is the wireless protocol.

'$SSID'
SSID is the name of the wireless network.

'$Security'
Security is the authentication protocol.

'$Channel'
This is the Channel, frequency and flags. 
On macOS 13 it looks like this: 5g44/80 (0x410).
Which translates to channel 44 on the 5gHZ frequency.  

'$IPv4'
The address of the laptop and the router.

'$DNS'
Domain Name Server is often the same as the router.

'$RSSI'
RSSI measures the power level of the WiFi signal received by the laptop. The scale is 0 (strongest) to -100 (weakest).

'$Noise'
Noise is a measure of the interference. The scale is 0 (most interference) to -120 (least interference).

'$TxRate'
Tx Rate is the maximum possible transmit/transfer rate for data on your network.
" with title "WiFi Info" with icon alias "System:Library:CoreServices:Applications:Wireless Diagnostics.app:Contents:Resources:AppIcon.icns" buttons {"OK"} default button 1'
