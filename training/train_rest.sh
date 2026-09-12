#!/bin/bash
set -e
cd "$(dirname "$0")"
for s in charmander squirtle; do
  echo "=== $s start $(date -u +%H:%M:%S) ==="
  python3 train.py "$s" 1400
  python3 verify_export.py "$s"
  echo "=== $s done $(date -u +%H:%M:%S) ==="
done
echo "ALL DONE"
