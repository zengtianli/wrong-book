#!/bin/bash
# Cheap compile lanes for Apple Watch and Vision Pro: no simulator, no Xcode project, no build products.
# Type-checks each target's own sources against the watchsimulator / xrsimulator SDKs with swiftc.
# The file lists come from project.yml (the same `sources:` the generated project uses), so a file
# added to a target without compiling on that platform fails here, not first in Xcode Cloud.
#   bash Tests/check-platform-typecheck.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Swift sources of one target in project.yml: its `- path:` entries (files, or directories expanded to *.swift).
sources() {
  python3 - "$1" <<'PY'
import re, sys
from pathlib import Path
target, lines = sys.argv[1], Path("project.yml").read_text(encoding="utf-8").splitlines()
inside = in_sources = False
out = []
for line in lines:
    if re.match(r"^  \S.*:\s*$", line):                    # a target key (two-space indent)
        inside = line.strip() == f"{target}:"
        in_sources = False
        continue
    if not inside:
        continue
    if re.match(r"^    \S", line):                          # a target property
        in_sources = line.strip() == "sources:"
        continue
    m = re.match(r"^\s+- path: (.+?)\s*$", line)
    if in_sources and m:
        p = Path(m.group(1).strip('"'))
        if p.suffix == ".swift":
            out.append(str(p))
        elif p.is_dir():
            out += sorted(str(f) for f in p.glob("*.swift"))
if not out:
    sys.exit(f"no Swift sources found for target {target} in project.yml")
print("\n".join(out))
PY
}

check() {
  local label="$1" sdk="$2" triple="$3"; shift 3
  local files=("$@")
  xcrun --sdk "$sdk" swiftc -typecheck -parse-as-library -swift-version 5 -enable-bare-slash-regex -target "$triple" "${files[@]}"
  echo "  ✅ $label: ${#files[@]} files type-check ($sdk, $triple)"
}

watch_app=(); while IFS= read -r f; do watch_app+=("$f"); done < <(sources WrongBookWatch)
watch_widget=(); while IFS= read -r f; do watch_widget+=("$f"); done < <(sources WrongBookWatchWidget)
check "watch app" watchsimulator arm64-apple-watchos11.0-simulator "${watch_app[@]}"
check "watch complications" watchsimulator arm64-apple-watchos11.0-simulator "${watch_widget[@]}"

# Vision Pro runs the same multiplatform target as iPhone/iPad/Mac: Shared + every file in Sources/.
vision_app=(); while IFS= read -r f; do vision_app+=("$f"); done < <(sources WrongBook)
check "vision app" xrsimulator arm64-apple-xros26.0-simulator "${vision_app[@]}"
echo "PASS: watchOS and visionOS sources type-check"
