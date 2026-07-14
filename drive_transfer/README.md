# Google Drive Recursive Ownership Transfer

Transfer ownership of a Google Drive folder and all its contents recursively using GAM7 and Python.

## Prerequisites

- [GAM7](https://github.com/GAM-team/GAM) installed and authenticated
- Python 3
- Admin or delegated access to the source user's Drive

---

## Files

| File | Description |
|---|---|
| `export.sh` | GAM commands to export folder and file data to CSV |
| `inspect.py` | Debug script to verify CSV structure before transferring |
| `transfer.py` | Recursive ownership transfer script |

---

## Workflow

### 1. Export owned files and folders

Run the GAM export commands to pull all files and folders owned by the current owner:

```bash
# All folders
gam user CURRENT_OWNER@DOMAIN.COM print filelist query "mimeType='application/vnd.google-apps.folder' and 'me' in owners" fields id,name,parents > folders.csv

# All owned files and folders
gam user CURRENT_OWNER@DOMAIN.COM print filelist query "'me' in owners" fields id,name,mimeType,parents > all_files.csv
```

---

### 2. Find the root folder ID

Navigate to the folder in Google Drive and copy the folder ID from the URL:

```
https://drive.google.com/drive/folders/FOLDER_ID_IS_HERE
```

---

### 3. Verify CSV structure

Before running the transfer, confirm the CSV is structured correctly and the parent IDs are resolving:

```bash
python3 inspect.py
```

Expected output shows items whose parent matches the root folder ID. If parents show as `'1'` the wrong column is being read — confirm the CSV has a `parents.0.id` column:

```bash
head -1 all_files.csv
```

---

### 4. Dry run

Open `transfer.py` and set your values:

```python
CURRENT_OWNER = "CURRENT_OWNER@DOMAIN.COM"
NEW_OWNER = "NEW_OWNER@DOMAIN.COM"
ROOT_FOLDER_ID = "YOUR_FOLDER_ID"
DRY_RUN = True
```

Run the dry run to print the full folder tree without making any changes:

```bash
python3 transfer.py
```

Review the output and confirm the correct files and folders are listed before proceeding.

---

### 5. Live run

Once the dry run looks correct, set `DRY_RUN = False` in `transfer.py` and run again:

```bash
python3 transfer.py
```

The script will print `OK` or `ERROR` for each item as it processes.

---

### 6. Clean up your access

If you added yourself as a writer to inspect the folder, remove your access after the transfer:

```bash
gam user NEW_OWNER@DOMAIN.COM delete drivefileacl ROOT_FOLDER_ID YOUR_EMAIL@DOMAIN.COM
```

---

## Notes

- Only files and folders owned by `CURRENT_OWNER` are transferred — items owned by others in the same folder are not touched
- The transfer is scoped to the `ROOT_FOLDER_ID` and its children only
- After transfer, the original owner is downgraded to editor
- Both users must be in the same Google Workspace domain
- The script handles up to 4 levels of nesting but will work for any depth
- Re-running the script is safe — GAM will no-op on items already transferred

---

## Troubleshooting

**`parents` column shows `'1'`**
The CSV column for parent IDs is `parents.0.id`, not `parents`. Run `head -1 all_files.csv` to confirm column names.

**Depth shows 0 for all folders**
Same root cause as above — parent IDs are not resolving. Verify the `parents.0.id` column exists in the CSV.

**GAM transfer ownership fails**
Confirm you are on GAM7. The correct syntax is:
```bash
gam user CURRENT_OWNER@DOMAIN.COM transfer ownership FILE_ID NEW_OWNER@DOMAIN.COM
```

**Permission denied on delete ACL**
Run the delete as the new owner rather than yourself:
```bash
gam user NEW_OWNER@DOMAIN.COM delete drivefileacl FOLDER_ID YOUR_EMAIL@DOMAIN.COM
```
