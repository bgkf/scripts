#!/usr/bin/env python3
import csv

ROOT_FOLDER_ID = "ROOT_FOLDER_ID"

with open('all_files.csv') as f:
    rows = list(csv.DictReader(f))

# Show items whose parent should be the root
print("=== ITEMS WITH ROOT AS PARENT ===")
for row in rows:
    parent = row.get('parents', '')
    if ROOT_FOLDER_ID in parent:
        print(repr(parent), row['name'])

# Show a few raw parent values so we can see the format
print("\n=== RAW PARENT SAMPLES ===")
for row in rows[:10]:
    print(repr(row.get('parents', '')), row['name'])