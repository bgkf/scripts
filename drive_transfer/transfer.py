#!/usr/bin/env python3
import csv
import subprocess

CURRENT_OWNER = "CURRENT_OWNER@DOMAIN.COM"
NEW_OWNER = "NEW_OWNER@DOMAIN.COM"
ROOT_FOLDER_ID = "ROOT_FOLDER_ID"
DRY_RUN = True

all_items = {}
children = {}

with open('all_files.csv') as f:
    for row in csv.DictReader(f):
        fid = row['id']
        parent = row.get('parents.0.id', '').strip()
        all_items[fid] = {'name': row['name'], 'mime': row['mimeType'], 'parent': parent}
        if parent not in children:
            children[parent] = []
        children[parent].append(fid)

def transfer(fid, depth=0):
    info = all_items.get(fid)
    if not info:
        return
    indent = "  " * depth
    print(f"{indent}[depth {depth}] {info['name']}  ({fid})")
    if not DRY_RUN:
        result = subprocess.run([
            "gam", "user", CURRENT_OWNER,
            "transfer", "ownership", fid,
            NEW_OWNER
        ], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"{indent}  ERROR: {result.stderr.strip()}")
        else:
            print(f"{indent}  OK")
    for child_id in children.get(fid, []):
        transfer(child_id, depth + 1)

print(f"=== {'DRY RUN' if DRY_RUN else 'LIVE RUN'} ===")
transfer(ROOT_FOLDER_ID)