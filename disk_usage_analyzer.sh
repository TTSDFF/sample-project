#!/usr/bin/env bash
set -euo pipefail

# Usage: ./disk_usage_analyzer.sh /path/to/dir [bar|pie]

ROOT="${1:-}"
CHART="${2:-bar}"

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "Usage: $0 /path/to/dir [bar|pie]"
  exit 1
fi

# On macOS 'du -b' isn’t available, so we detect and use 'du -k' * 1024
if [[ "$(uname)" == "Darwin" ]]; then
  DU_CMD=(du -k -d 1 "$ROOT")
  CONVERT_TO_BYTES='*1024'
else
  DU_CMD=(du -b --max-depth=1 "$ROOT")
  CONVERT_TO_BYTES=''
fi

# Build a temporary CSV of name,size
TMPCSV="$(mktemp /tmp/du_XXXXXX.csv)"
echo "name,size" > "$TMPCSV"

# Skip the first line (the root itself) if you don’t want “.,” entry;
# here we include it as “.” so you see files in the root.
"${DU_CMD[@]}" 2>/dev/null \
  | awk -v conv="$CONVERT_TO_BYTES" '
      {
        size = $1 conv
        # strip the parent path, keep basename
        n = $2
        sub(".*/", "", n)
        if (n=="") n="."
        print n","size
      }
    ' >> "$TMPCSV"

# Now invoke Python for plotting
python3 - "$TMPCSV" "$CHART" <<'PYCODE'
import sys
import csv
import matplotlib.pyplot as plt

csv_file, chart = sys.argv[1], sys.argv[2]

# Read data
names, sizes = [], []
with open(csv_file) as f:
    reader = csv.DictReader(f)
    for row in reader:
        names.append(row['name'])
        sizes.append(int(row['size']))

# Sort descending
pairs = sorted(zip(sizes, names), reverse=True)
sizes, names = zip(*pairs)

def human(n):
    for unit in ['B','KB','MB','GB','TB']:
        if n < 1024: return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}PB"

plt.figure(figsize=(8,6))
if chart == 'pie':
    labels = [f"{nm} ({human(sz)})" for sz,nm in zip(sizes, names)]
    plt.pie(sizes, labels=labels, autopct='%1.1f%%', startangle=140)
    plt.title("Disk Usage Breakdown")
else:
    plt.bar(range(len(sizes)), sizes, edgecolor='black')
    plt.xticks(range(len(sizes)), names, rotation=45, ha='right')
    plt.ylabel("Bytes")
    plt.title("Disk Usage per Top-Level Entry")
    plt.tight_layout()

plt.show()
PYCODE

# Clean up
rm "$TMPCSV"

