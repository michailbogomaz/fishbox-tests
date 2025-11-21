#!/usr/bin/env bash
# Script to rename all files in files/ directory to fish_catch_test{N}.jpeg pattern

set -euo pipefail

FILES_DIR="./files"

if [ ! -d "$FILES_DIR" ]; then
  echo "ERROR: Directory $FILES_DIR not found" >&2
  exit 1
fi

cd "$FILES_DIR"

# Get all image files, sorted
files=$(find . -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) | sed 's|^\./||' | sort)

if [ -z "$files" ]; then
  echo "No image files found in $FILES_DIR"
  exit 0
fi

count=$(echo "$files" | wc -l | tr -d ' ')
echo "Found $count files to rename"
echo ""

counter=1
renamed=0
skipped=0

while IFS= read -r old_name; do
  if [ -z "$old_name" ]; then
    continue
  fi
  
  # Generate new name
  new_name="fish_catch_test${counter}.jpeg"
  
  # Skip if already has correct name
  if [ "$old_name" = "$new_name" ]; then
    echo "[$counter/$count] ✓ Already correct: $old_name"
    ((skipped++)) || true
  else
    # Check if target name already exists
    if [ -f "$new_name" ] && [ "$old_name" != "$new_name" ]; then
      echo "[$counter/$count] ⚠ Target exists, skipping: $old_name -> $new_name"
      ((skipped++)) || true
    else
      # Rename file
      mv "$old_name" "$new_name"
      echo "[$counter/$count] ✓ Renamed: $old_name -> $new_name"
      ((renamed++)) || true
    fi
  fi
  
  ((counter++)) || true
done <<< "$files"

echo ""
echo "Complete! Renamed: $renamed, Skipped: $skipped, Total: $count"

