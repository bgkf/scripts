### TCC Modified ###

This is a collection of methods to gather data about TCC database. Transparency, Consent and Control settings are managed in the Security and Privacy window of System Settings. The log searches can be used to create alerts when a change is made and the queries can be used to investigate the current settings.
<br><br>

Unified log search to show all TCCd process events with a type of Modify:<br>
```
sudo log show --predicate 'process == "tccd" && eventMessage CONTAINS "Publishing <TCCDEvent: type=Modify"'
```

Example log search result:<br>
>2025-11-24 09:59:53.548358-0800 0x4346f6   Default     0xb5e229             1235   0    tccd: [com.apple.TCC:events] Publishing <TCCDEvent: type=Modify, service=kTCCServiceMicrophone, identifier_type=Bundle ID, identifier=com.tinyspeck.slackmacgap> to 3 subscribers: {<br>
    582 = "<TCCDEventSubscriber: token=582, state=Passed, csid=com.apple.chronod>";<br>
    478 = "<TCCDEventSubscriber: token=478, state=Passed, csid=com.apple.photolibraryd>";<br>
    461 = "<TCCDEventSubscriber: token=461, state=Initial, csid=(null)>";<br>
}
<br>

Jamf Protect log search:<br>
```
process == "tccd" && eventMessage CONTAINS "Publishing <TCCDEvent: type=Modify"
```
<br>

Script to query the TCC database for current settings:<br>
```
#! /bin/zsh

sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db << 'END_SQL'
	SELECT service, client, auth_value, last_modified FROM access;
END_SQL
```
<br>

Example script result:<br> 
>kTCCServiceScreenCapture|Cisco-Systems.Spark|0|1744405886
kTCCServiceScreenCapture|com.cisco.webexmeetingsapp|0|1744405886
kTCCServiceScreenCapture|com.microsoft.teams|0|1744405886
kTCCServiceScreenCapture|com.webex.meetingmanager|0|1744405886
kTCCServiceSystemPolicyAllFiles|com.google.GoogleUpdater|0|1745538132
kTCCServiceScreenCapture|us.zoom.xos|2|1747246606
kTCCServiceScreenCapture|com.tinyspeck.slackmacgap|2|1747246610
kTCCServiceScreenCapture|com.google.Chrome|2|1747246614
kTCCServiceSystemPolicyAllFiles|com.jamfsoftware.Composer|2|1750889128
kTCCServiceEndpointSecurityClient|io.osquery.agent|0|1755279442
kTCCServiceSystemPolicyAllFiles|com.google.drivefs|0|1759514954
kTCCServiceSystemPolicyAllFiles|com.apple.dt.Xcode|0|1759528673
kTCCServiceAccessibility|com.anthropic.claudefordesktop|0|1761076561
kTCCServiceSystemPolicyAllFiles|com.jamf.protect.security-extension|0|1763665298
kTCCServiceDeveloperTool|com.apple.Terminal|0|1764007140
kTCCServiceScreenCapture|com.apple.Safari|0|1764007219
<br>

Using OSQuery you can enable [Automatic Table Construction](https://osquery.readthedocs.io/en/stable/deployment/configuration/#:~:text=Automatic%20Table%20Construction).
<br>
