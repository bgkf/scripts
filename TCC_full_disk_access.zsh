#! /bin/zsh

# Get all services with full disk access.

sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db << 'END_SQL' 
.timeout 2000 
SELECT service, client, client_type, auth_value, auth_reason, auth_version FROM access WHERE service = "kTCCServiceSystemPolicyAllFiles" AND auth_value = 2; 
END_SQL
