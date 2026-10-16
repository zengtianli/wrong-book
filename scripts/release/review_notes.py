#!/usr/bin/env python3
"""Write/read back this product's draft Review Notes through the existing ASC engine.

Never attaches a build, submits a review, prints review credentials or changes
the shared product catalog. Answers stay in the product's review directory;
private Notes inputs and readback receipts stay in handoffs/.
"""
import argparse
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
ANSWERS = ROOT.parent / "02-审核/当前版本/01-问题与回复/4.3-4.2.6-九问.md"
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import asc
import asc_listing


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--version", required=True)
    p.add_argument("--notes", type=Path, required=True)
    p.add_argument("--answers", type=Path, default=ANSWERS)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--apply", action="store_true")
    args = p.parse_args()
    for path in (args.notes, args.out):
        path.resolve().relative_to(ROOT / "handoffs")
    if args.answers.resolve() != ANSWERS.resolve():
        p.error("use this product's canonical nine-answer file")
    if args.out.exists():
        p.error("preserve prior receipts; --out must be new")
    notes = args.notes.read_text().strip()
    answers = args.answers.read_bytes()
    if not notes or len(notes) > 4000:
        p.error("Review Notes must contain 1–4000 characters")
    if set(re.findall(r"^## ([1-9])\.", answers.decode(), re.M)) != set("123456789"):
        p.error("nine answers are incomplete")
    row = asc_listing.load_product("wrong-book-ios")
    if Path(row["repo"]).expanduser().resolve() != ROOT:
        p.error("catalog points to another repository")
    bundle = asc_listing.bundle_id_of(row)
    if bundle != "cyou.tianli.wrongbook":
        p.error("unexpected product bundle")
    app_id = "6806626967"
    if asc.get("/apps/" + app_id)["data"]["attributes"]["bundleId"] != bundle:
        p.error("ASC App identity differs")
    versions = asc._versions(app_id, "IOS")
    target = next((v for v in versions if v["versionString"] == args.version), None)
    if not target and args.apply:
        with contextlib.redirect_stdout(io.StringIO()):
            versions = asc.ensure_version(app_id, "IOS", args.version)
        target = next((v for v in versions if v["versionString"] == args.version), None)
    if target is None:
        p.error("target draft does not exist; --apply can create it")
    if target["appStoreState"] not in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
        p.error("target is not an editable draft; no review state is changed")
    original = asc.get(f"/appStoreVersions/{target['id']}/appStoreReviewDetail").get("data")
    already_matches = bool(original and original.get("attributes", {}).get("notes", "") == notes)
    if args.apply and not already_matches:
        scoped = copy.deepcopy(row)
        scoped["store"]["demo"]["notes"] = notes
        with contextlib.redirect_stdout(io.StringIO()):
            ctx = asc_listing.AppCtx(scoped)
            if ctx.version_id != target["id"]:
                p.error("listing engine selected another draft")
            asc_listing.do_review(ctx)
    actual = asc.get(f"/appStoreVersions/{target['id']}/appStoreReviewDetail")["data"]
    attributes = actual["attributes"] if actual else {}
    readback = attributes.get("notes", "")
    if readback != notes:
        raise RuntimeError("official Review Notes readback differs")
    after = asc.get(f"/appStoreVersions/{target['id']}", {"include": "build"})["data"]
    result = {"app_id": app_id, "bundle_id": bundle, "version": args.version,
              "version_id": target["id"], "review_detail_id": actual["id"],
              "state": after["attributes"]["appStoreState"], "notes_readback_matches": True,
              "notes_sha256": sha(readback.encode()), "answers_sha256": sha(answers),
              "notes_characters": len(notes), "applied": args.apply and not already_matches,
              "already_matched": already_matches,
              "build": after.get("relationships", {}).get("build", {}).get("data"),
              "submission_performed": False}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    args.out.chmod(0o600)
    args.out.with_suffix(".notes.txt").write_text(readback + "\n")
    args.out.with_suffix(".notes.txt").chmod(0o600)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
