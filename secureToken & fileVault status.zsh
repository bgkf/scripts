#! /bin/zsh

loggedInUser=$(stat -f "%Su" /dev/console) 

filevaultUser=$(fdesetup list | cut -d "," -f 1)

echo ""
echo "The FileVault enabled user is $filevaultUser"
echo ""
echo "$(sysadminctl -secureTokenStatus wellthyitadmin 2>&1 | cut -d " " -f 4-12)"
echo ""
echo "$(sysadminctl -secureTokenStatus "${loggedInUser}" 2>&1 | cut -d " " -f 4-12)"
echo ""