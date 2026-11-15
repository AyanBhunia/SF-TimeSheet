#!/usr/bin/env bash
set -euo pipefail

# Ensure xmllint is available
if ! command -v xmllint &>/dev/null; then
  if command -v apt-get &>/dev/null; then
    echo "xmllint not found; installing libxml2-utils..."
    sudo apt-get update -qq && sudo apt-get install -y -qq libxml2-utils
  else
    echo "ERROR: xmllint command not found." >&2
    exit 1
  fi
fi

BASE_REF="${BASE_REF:-origin/${GITHUB_BASE_REF:-appexchange}}"

# If files are passed as arguments, check those; otherwise determine changed XML files via git diff
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=()
  while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
  done < <(git diff --name-only --diff-filter=d "${BASE_REF}...HEAD" -- '*.xml' 2>/dev/null || git diff --name-only --diff-filter=d HEAD -- '*.xml' 2>/dev/null || true)
fi

if [ ${#files[@]} -eq 0 ]; then
  echo "No changed XML files to check."
  exit 0
fi

echo "Checking ${#files[@]} XML file(s) for well-formedness..."
failed=0

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    if ! xmllint --noout "$file"; then
      echo "FAIL: Malformed XML in $file" >&2
      failed=1
    else
      echo "PASS: $file"
    fi
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "XML well-formedness check failed." >&2
  exit 1
fi

echo "All checked XML files are well-formed."
exit 0
