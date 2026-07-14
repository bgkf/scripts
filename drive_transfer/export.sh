#!/bin/bash

CURRENT_OWNER="CURRENT_OWNER@DOMAIN.COM"

# All folders owned by user
gam user "$CURRENT_OWNER" print filelist query "mimeType='application/vnd.google-apps.folder' and 'me' in owners" fields id,name,parents > folders.csv

# All owned files and folders
gam user "$CURRENT_OWNER" print filelist query "'me' in owners" fields id,name,mimeType,parents > all_files.csv
