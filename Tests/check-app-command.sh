#!/bin/bash
# The Mac app executable's command entry (Sources/AppCommand.swift: config / update / offline / app), run in isolation.
# Compiles the WrongBook target's own sources (project.yml list) for macOS into a scratch binary — no Xcode project,
# no bundle, no sandbox, no window — and drives the commands with a temporary HOME, an isolated lifecycle support
# directory and an isolated update directory. Nothing here reads or writes the installed app, its container,
# its preferences or the real iCloud Drive. One thing does leave the temporary HOME: the preferences daemon ignores
# it, so the unbundled binary's own UserDefaults land in a throwaway domain named after the binary
# (WrongBookCommandCheck, not the app's cyou.tianli.wrongbook); the script deletes that domain when it exits.
#   bash Tests/check-app-command.sh [--keep <dir>]     (--keep leaves the binary in <dir>)
#   WRONGBOOK_COMMAND_BIN=<binary> bash Tests/check-app-command.sh     (reuse a binary this script built; skips the compile)
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d /tmp/wrongbook-command.XXXXXX)"
keep=""; [ "${1:-}" = "--keep" ] && keep="$2"
trap 'rm -rf "$scratch"; defaults delete WrongBookCommandCheck >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/WrongBookCommandCheck.plist"' EXIT

files=(); while IFS= read -r f; do files+=("$f"); done < <(python3 - <<'PY'
import re
from pathlib import Path
out, inside, in_sources = [], False, False
for line in Path("project.yml").read_text(encoding="utf-8").splitlines():
    if re.match(r"^  \S.*:\s*$", line):
        inside, in_sources = line.strip() == "WrongBook:", False
        continue
    if not inside:
        continue
    if re.match(r"^    \S", line):
        in_sources = line.strip() == "sources:"
        continue
    m = re.match(r"^\s+- path: (.+?)\s*$", line)
    if in_sources and m:
        p = Path(m.group(1))
        out += [str(p)] if p.suffix == ".swift" else sorted(str(f) for f in p.glob("*.swift")) if p.is_dir() else []
print("\n".join(out))
PY
)
bin="$scratch/WrongBookCommandCheck"
if [ -n "${WRONGBOOK_COMMAND_BIN:-}" ]; then cp "$WRONGBOOK_COMMAND_BIN" "$bin"; echo "  ℹ️  reusing $WRONGBOOK_COMMAND_BIN"; else
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 -enable-bare-slash-regex -D APP_LIFECYCLE_KVS -Onone \
  -target "$(uname -m)-apple-macos15.0" -module-name WrongBook -o "$bin" "${files[@]}" 2> "$scratch/build.log" \
  || { grep -E "error" "$scratch/build.log" | head -40; echo "FAIL: Mac sources do not compile"; exit 1; }
echo "  ✅ ${#files[@]} files compile for macOS with the command entry"
fi
[ -n "$keep" ] && mkdir -p "$keep" && cp "$bin" "$keep/WrongBookCommandCheck"

home="$scratch/home"; mkdir -p "$home" "$scratch/support" "$scratch/cloud"
fails=0
# run <expected exit> <label> <args…>: output lands in $scratch/out
run() {
  local want="$1" label="$2"; shift 2
  local code=0
  env -i PATH=/usr/bin:/bin HOME="$home" CFFIXED_USER_HOME="$home" TMPDIR="$scratch" \
    APP_LIFECYCLE_SUPPORT_DIR="$scratch/support" APP_LIFECYCLE_CLOUD_DIR="$scratch/cloud" APP_LIFECYCLE_NO_RELAUNCH=1 \
    ${IMPORT_LABEL:+MISTAKES_IMPORT_PATH="$IMPORT_LABEL"} \
    "$bin" "$@" > "$scratch/out" 2> "$scratch/err" || code=$?
  if [ "$code" = "$want" ]; then echo "  ✅ $label → $code"; else echo "  ❌ $label → $code (want $want)"; cat "$scratch/out" "$scratch/err" | head -12; fails=$((fails + 1)); fi
}
# has <label> <python expression over d>: checks the last JSON output
has() {
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2]) else 1)' "$scratch/out" "$2" 2>/dev/null
  then echo "  ✅ $1"; else echo "  ❌ $1"; head -c 600 "$scratch/out"; echo; fails=$((fails + 1)); fi
}

run 0 "config status --json" config status --json
has "config status: the two reminder settings are the portable keys, sync off, sync_status present" \
  'd["ok"] and d["has_settings"] and d["sync_enabled"] is False and d["sync_status"]["text"] and d["command"]=="config status"'
run 0 "config export -o" config export -o "$scratch/config.json" --json
has "config export wrote the file" 'd["ok"] and d["bytes"] > 0'
python3 - "$scratch/config.json" "$scratch/import.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["values"].update({"defaults.remind_enabled": True, "defaults.remind_hour": 7})
json.dump(d, open(sys.argv[2], "w"))
d["values"]["defaults.api_base"] = "http://example.invalid"
json.dump(d, open(sys.argv[1].replace("config.json", "after.bad.json"), "w"))
PY
run 2 "config import without --yes" config import "$scratch/import.json" --json
has "config import asks for --yes" 'd["error"]["code"]=="confirmation_required"'
run 0 "config import --yes" config import "$scratch/import.json" --yes --json
run 0 "config export after import" config export -o "$scratch/after.json" --force --json
run 2 "config import - (standard input) without --yes" config import - --json < "$scratch/import.json"
has "import from standard input asks for --yes" 'd["error"]["code"]=="confirmation_required"'
sed 's/"defaults.remind_hour": 7/"defaults.remind_hour": 21/' "$scratch/import.json" > "$scratch/import-stdin.json"
IMPORT_LABEL="/caller/config.json" run 0 "config import - --yes (standard input)" config import - --yes --json < "$scratch/import-stdin.json"
has "import from standard input applied; the path shown is the caller's file name" 'd["ok"] and d["imported"] and d["path"]=="/caller/config.json"'
run 0 "config export -o - after the standard-input import" config export -o -
has "the value imported from standard input reads back (remind_hour 21)" 'd["values"]["defaults.remind_hour"]==21'
if ls "$scratch" | grep -q '^mistakes-import-'; then echo "  ❌ staged import file left behind"; fails=$((fails + 1)); else echo "  ✅ the staged import file is gone"; fi
run 0 "config import --yes (back to hour 7)" config import "$scratch/import.json" --yes --json
if python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["values"]; sys.exit(0 if v.get("defaults.remind_enabled") is True and v.get("defaults.remind_hour")==7 else 1)' "$scratch/after.json"
then echo "  ✅ reminder switch and hour read back after import (remind_enabled true, remind_hour 7)"
else echo "  ❌ reminder settings did not read back"; cat "$scratch/after.json"; fails=$((fails + 1)); fi
run 0 "config sync on --dry-run" config sync on --dry-run --json
run 0 "config status after import" config status --json
has "config status lists the two reminder keys" 'd["keys"]==["defaults.remind_enabled","defaults.remind_hour"] and d["sync_enabled"] is False'
run 1 "config import of a key outside the list" config import "$scratch/after.bad.json" --yes --json
has "a foreign key is rejected, settings kept" 'd["error"]["code"] in ("import_rejected","not_found")'
run 0 "config sync on --dry-run (again)" config sync on --dry-run --json
has "config sync dry run would change, nothing written" 'd["would_change"] is True and d["sync_enabled"] is False'
run 2 "config sync on without --yes" config sync on --json
run 2 "config with an unknown flag" config status --no-such --json
has "usage error shape" 'd["ok"] is False and d["error"]["code"]=="usage"'

run 1 "update check with no release record" update check --json
has "update check reports check_incomplete with current and source" 'd["error"]["code"]=="check_incomplete" and d["source"]["kind"]=="private_cloud" and "current" in d'
run 1 "update install --yes with no release record" update install --yes --json
has "update install stops at check_incomplete, nothing replaced" 'd["error"]["code"]=="check_incomplete"'
run 2 "update with an unknown subcommand" update nope --json
has "update usage error" 'd["error"]["code"]=="usage"'

run 2 "offline reset without --yes" offline reset --json
has "offline reset asks for --yes" 'd["error"]["code"]=="confirmation_required"'
run 0 "offline reset --yes (no copy)" offline reset --yes --json
has "offline reset reports files kept" 'd["ok"] and d["reset"] and d["files_kept"] and d["had_active_copy"] is False'
run 2 "app logout without --yes" app logout --json
has "app logout asks for --yes" 'd["error"]["code"]=="confirmation_required"'
run 2 "offline with an unknown subcommand" offline nope --json
run 2 "app with an extra argument" app logout extra --yes --json

# offline / logout against the repo's fictional demo library (scripts/demo/fixture.py: its own local server and an
# invented account; -api_base / -dev_user / -dev_pw are the app's existing verification launch arguments).
fx="$(python3 scripts/demo/fixture.py start --dir "$scratch/fixture" --json)"
trap 'python3 scripts/demo/fixture.py stop --dir "$scratch/fixture" >/dev/null 2>&1 || true; rm -rf "$scratch"; defaults delete WrongBookCommandCheck >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/WrongBookCommandCheck.plist"' EXIT
field() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$fx" "$1"; }
url="$(field url)"; user="$(field user)"; pw="$(field pw)"
copies="$home/Library/Application Support/wrong-book/private-v2"
run 1 "offline sync when the app is not signed in" offline sync --json -api_base "$url"
has "offline sync reports not_signed_in" 'd["error"]["code"]=="not_signed_in"'
run 1 "offline sync with no server" offline sync --json -api_base "http://127.0.0.1:9"
has "offline sync reports unreachable" 'd["error"]["code"]=="unreachable"'
run 0 "offline sync (demo account)" offline sync --json -api_base "$url" -dev_user "$user" -dev_pw "$pw"
has "offline sync pulled the five demo lessons and read them back from disk" \
  'd["ok"] and d["synced"] and d["active"] and d["count"]==5 and all(l["on_disk"] and l["bytes"]>0 and len(l["sha256"])==64 for l in d["lessons"]) and "/wrong-book/private-v2/" in d["directory"]'
pages="$(find "$copies" -name '*.html' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$pages" = 5 ]; then echo "  ✅ the copies are under the temporary HOME (5 pages)"; else echo "  ❌ expected 5 pages under the temporary HOME, found $pages"; fails=$((fails + 1)); fi
run 0 "offline reset --yes (after a sync)" offline reset --yes --json
has "offline reset cleared the pointer of an active copy" 'd["reset"] and d["had_active_copy"] is True and d["files_kept"]'
pages="$(find "$copies" -name '*.html' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$pages" = 5 ]; then echo "  ✅ personal files are still on disk after the reset"; else echo "  ❌ files after reset: $pages"; fails=$((fails + 1)); fi
run 0 "offline reset --yes again" offline reset --yes --json
has "second reset finds nothing active" 'd["had_active_copy"] is False'
run 0 "app logout --yes (signed in through the verification arguments)" app logout --yes --json -api_base "$url" -dev_user "$user" -dev_pw "$pw"
has "app logout ended the session and left no session cookie" 'd["logged_out"] and d["had_session"] is True and d["session_cookie_left"] is False'
run 0 "app logout --yes when not signed in" app logout --yes --json -api_base "$url"
has "logout without a session changes nothing" 'd["logged_out"] and d["had_session"] is False'
run 1 "offline sync after logout" offline sync --json -api_base "$url"
has "after logout the app is not signed in" 'd["error"]["code"]=="not_signed_in"'

[ "$fails" = 0 ] && echo "PASS: app command entry (isolated)" || { echo "FAIL: $fails check(s)"; exit 1; }
