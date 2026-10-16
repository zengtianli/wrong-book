#!/bin/bash
# Consume completed native-flow evidence; never send SMS, mutate accounts or turn mocks into a pass.
set -euo pipefail
cd "$(dirname "$0")/../.."
# A separate real-product producer may add five no-message cases. It cannot
# certify email/SMS, registration or recovery; the strict consumer below keeps
# every remaining live-channel case pending. Missing candidate/queue busy is 75.
if [ "${SOP_ACCOUNT_PRODUCE:-1}" = 1 ]; then
    producer_code=0
    "$HOME/Dev/.venv/bin/python" scripts/accept/account_native.py --produce || producer_code=$?
    if [ "$producer_code" != 0 ] && [ "$producer_code" != 75 ]; then
        echo "原生账号生产者失败；先查 perf/account/native-*/failed.json" >&2
        exit "$producer_code"
    fi
fi
exec "$HOME/Dev/.venv/bin/python" - <<'PY'
import json
import os
from pathlib import Path
import sys

repo = Path.cwd()
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import app_sop
import yaml

registered = yaml.safe_load((repo / "project.yaml").read_text())
config = json.loads(os.environ["SOP_CONFIG"]) if os.environ.get("SOP_CONFIG") else registered["sop"]
app = {"id": "wrong-book-ios", "repo": repo, "sop": config,
       "form": registered["form"], "bundle_id": registered["bundle_id"], "row": None}
expected = app_sop.monitor_inputs(app, {})["bindings"]["account"]
source = repo / "perf/account/account-lifecycle.json"
issues = []
if source.is_file():
    try:
        detail = json.loads(source.read_text())
        if not isinstance(detail, dict):
            raise ValueError("账号证据索引须为对象")
    except (ValueError, OSError):
        detail = {}
        issues.append("账号证据索引不可读")
else:
    detail = {}
    issues.append("缺少 perf/account/account-lifecycle.json 原生实际流程证据索引")
issues.extend(app_sop.account_evidence_issues(app, detail))
if detail.get("account_input_sha256") != expected:
    issues.append("原生账号验收未绑定当前客户端和共享账号服务输入")
detail.update(expected_account_input_sha256=expected, issues=issues)
if issues:
    detail["summary"] = "账号闭环待实际验收：" + "；".join(issues)
else:
    detail["summary"] = "原生账号流程和真实邮件、短信的逐项证据均已核验"
out = Path(os.environ.get("SOP_OUT_DIR", str(repo / "perf/acceptance")))
out.mkdir(parents=True, exist_ok=True)
target = out / "account_lifecycle.detail.json"
temporary = target.with_suffix(".tmp")
temporary.write_text(json.dumps(detail, ensure_ascii=False, indent=2) + "\n")
temporary.replace(target)
print(detail["summary"])
raise SystemExit(75 if issues else 0)
PY
