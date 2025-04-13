#! /bin/bash

result="Not installed"

loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
codePath="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

if [[ -e "${codePath}" ]]; then
  result=$(sudo -u "${loggedInUser}" "${codePath}" --list-extensions --show-versions)
fi

if [[ -z "${result}" ]]; then
  result="No extensions found"
fi

echo "<result>${result}</result>"