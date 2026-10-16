"""Check recording boundaries in a disposable repository, never production media."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("compact_record", Path(__file__).resolve().parents[1] / "scripts/media/compact_unchanged.py")
compact = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compact)


class RecordBoundary(unittest.TestCase):
    def test_external_record_rejected_before_any_write(self):
        previous = compact.REPO
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                repo = root / "repo"; repo.mkdir()
                original = root / "original.json"; original.write_text('{"ui_reviews": []}')
                (repo / "project.yaml").write_text('sop:\n  media_meta: ../original.json\n')
                compact.REPO = repo
                with self.assertRaisesRegex(ValueError, "本仓派生"):
                    compact.record({}, root / "absent-summary.json")
                self.assertEqual(original.read_text(), '{"ui_reviews": []}')
                self.assertFalse((repo / "perf").exists())
        finally:
            compact.REPO = previous

    def test_local_failed_review_does_not_rewrite_original(self):
        previous = compact.REPO
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                repo = root / "repo"; repo.mkdir()
                original = root / "original.json"; original.write_text('{"ui_reviews": []}')
                meta = repo / "meta.json"
                pointer = {"path": str(original), "sha256": compact.sha(original), "access": "read_only"}
                meta.write_text(json.dumps({"original_record": pointer, "ui_reviews": []}))
                (repo / "project.yaml").write_text('sop:\n  media_meta: meta.json\n')
                compact.REPO = repo
                kept = repo / "perf/media/compact-unchanged.json"
                kept.parent.mkdir(parents=True)
                kept.write_text('{"previous_raw": true}')
                previous_sha = compact.sha(kept)
                report = {"checked_at": "test", "base_commit": "test", "ui_source": {"sha256": "test", "globs": []},
                          "unchanged": False, "device": "test fixture", "rule": "test", "verdict_screens": [], "screens": {}}
                summary = root / "summary.json"; summary.write_text(json.dumps(report))
                compact.record(report, summary)
                result = json.loads(meta.read_text())
                self.assertIs(result["ui_reviews"][-1]["unchanged"], False)
                self.assertEqual(result["original_record"], pointer)
                self.assertEqual(compact.sha(original), pointer["sha256"])
                self.assertEqual(compact.sha(repo / "perf/media/compact-unchanged.json"), compact.sha(summary))
                self.assertEqual(compact.sha(repo / "perf/media/previous-reviews" / (previous_sha + ".json")), previous_sha)
        finally:
            compact.REPO = previous


if __name__ == "__main__":
    unittest.main()
