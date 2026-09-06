#!/bin/bash
# Public installations begin empty. Personal uploads never enter a distributable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
python3 - "$ROOT" <<'PY'
import json, sys, time
from pathlib import Path
root = Path(sys.argv[1])
dst = root / 'Resources/Lessons'
# Retain historical exports outside the resources copied into the app.
if dst.exists() and any(p.name not in {'manifest.json', 'README.md'} for p in dst.iterdir()):
    quarantine = root / '.build-inputs' / ('retired-lessons-' + str(time.time_ns()))
    quarantine.parent.mkdir(parents=True, exist_ok=True)
    dst.rename(quarantine)
dst.mkdir(parents=True, exist_ok=True)
(dst / 'manifest.json').write_text(json.dumps({'schema': 2, 'distribution': 'empty-personal-library', 'daily_goal': 12, 'lessons': []}) + '\n')
(dst / 'README.md').write_text('# Personal library\n\nThe public app contains no lessons. Users import their own photographs.\n')
assert set(p.name for p in dst.iterdir()) == {'manifest.json', 'README.md'}, 'Unexpected public resource'
assert json.loads((dst / 'manifest.json').read_text())['lessons'] == []
print('Public bundle verified: 0 lessons; personal data is not exported.')
PY
