"""Offline localization regression checks; no simulator or live account is used.

The scanner reads Swift literals (including nested interpolation) rather than
grepping source lines, so comments and protocol expressions cannot hide missing
UI translations. Downloaded questions, user names, HTML, and shared source are
outside this product's bundled-copy assertion.
"""

from __future__ import annotations

from dataclasses import dataclass
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import unicodedata
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
CATALOG_DIR = ROOT / "Resources/Localization"
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\U00020000-\U0003134f]")
HAN_RUN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\U00020000-\U0003134f]+")
ARG = "\x00ARG\x00"
OPENING = re.compile(r'(#+)?("""|")')
UI_FILES = (
    "Sources/AIAccessSection.swift", "Sources/AccountSecurity.swift",
    "Sources/App.swift", "Sources/FocusLibraryView.swift",
    "Sources/HomeView.swift", "Sources/LearnView.swift",
    "Sources/LessonWebView.swift", "Sources/LoginView.swift",
    "Sources/MeView.swift", "Sources/MobileProductLifecycle.swift",
    "Sources/PaperScanView.swift", "Sources/ProductSettings.swift",
    "Sources/RegisterView.swift", "Sources/RegularHomeView.swift",
    "Sources/Reminder.swift", "Watch/App/WatchHomeView.swift", "Watch/App/WrongBookWatchApp.swift",
    "Watch/Common/ComplicationViews.swift",
    "Watch/Complications/ReviewComplications.swift",
)
RAW_ERROR_EXCEPTIONS = {
    "Sources/AccountSecurity.swift": {
        "未收到验证请求编号，请稍后重试", "未收到验证授权，请重新验证",
    },
    "Sources/MobileProductLifecycle.swift": {
        "提醒时间须为 1–23 时，原配置已保留。", "开关须为布尔值，原配置已保留。",
        "快捷键格式不正确。", "此字段不属于可迁移配置。",
    },
    "Sources/ProductSettings.swift": {
        "配置格式不正确，原配置已保留。", "此字段不属于可迁移配置。",
        "快捷键格式不正确。", "快捷键与本 App 菜单冲突，原配置已保留。",
    },
}


@dataclass(frozen=True)
class Literal:
    path: str
    line: int
    start: int
    end: int
    value: str
    localized: bool


class SwiftStrings:
    """Small lexer for comments, escaped/raw strings, and Swift interpolation."""

    def __init__(self, path: str, source: str):
        self.path, self.source = path, source
        self.literals: list[Literal] = []

    def scan(self) -> list[Literal]:
        self._code(0, len(self.source))
        return sorted(self.literals, key=lambda item: item.start)

    def _comment(self, pos: int) -> int | None:
        if self.source.startswith("//", pos):
            end = self.source.find("\n", pos)
            return len(self.source) if end < 0 else end
        if self.source.startswith("/*", pos):
            level, pos = 1, pos + 2
            while pos < len(self.source) and level:
                if self.source.startswith("/*", pos):
                    level, pos = level + 1, pos + 2
                elif self.source.startswith("*/", pos):
                    level, pos = level - 1, pos + 2
                else:
                    pos += 1
            return pos
        return None

    def _opening(self, pos: int) -> tuple[str, str, int] | None:
        match = OPENING.match(self.source, pos)
        if not match:
            return None
        hashes, quotes = match.group(1) or "", match.group(2)
        return hashes, quotes, pos + len(match.group(0))

    def _code(self, pos: int, end: int, interpolation: bool = False) -> int:
        depth = 1
        while pos < end:
            comment_end = self._comment(pos)
            if comment_end is not None:
                pos = comment_end
            elif self._opening(pos):
                pos = self._string(pos)
            elif interpolation and self.source[pos] == "(":
                depth, pos = depth + 1, pos + 1
            elif interpolation and self.source[pos] == ")":
                depth -= 1
                if depth == 0:
                    return pos
                pos += 1
            else:
                pos += 1
        return pos

    def _string(self, start: int) -> int:
        hashes, quotes, pos = self._opening(start)
        closing, escape = quotes + hashes, "\\" + hashes
        value: list[str] = []
        while pos < len(self.source):
            if self.source.startswith(closing, pos):
                end = pos + len(closing)
                prefix = self.source[max(0, start - 100):start]
                localized = bool(re.search(r"String\s*\(\s*localized:\s*$", prefix))
                self.literals.append(Literal(
                    self.path, self.source.count("\n", 0, start) + 1,
                    start, end, "".join(value), localized,
                ))
                return end
            if self.source.startswith(escape + "(", pos):
                pos = self._code(pos + len(escape) + 1, len(self.source), True) + 1
                value.append(ARG)
            elif self.source.startswith(escape, pos):
                char_pos = pos + len(escape)
                if char_pos >= len(self.source):
                    break
                char = self.source[char_pos]
                value.append({"n": "\n", "r": "\r", "t": "\t", "0": "\0"}.get(char, char))
                pos = char_pos + 1
            else:
                value.append(self.source[pos])
                pos += 1
        raise AssertionError(f"Unterminated Swift string at {self.path}:{start}")


FORMAT = re.compile(r"%(?:(\d+)\$)?[-+ 0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|ll|h|l|q|z|t|j)?([@diuoxXfFeEgGaAcCsSp])")


def format_args(value: str) -> list[tuple[int, str]]:
    """Retain argument positions and types, allowing English word reordering."""
    output, automatic = [], 0
    for match in FORMAT.finditer(value.replace("%%", "")):
        automatic += 1
        output.append((int(match.group(1) or automatic), (match.group(2) or "") + match.group(3)))
    return sorted(output)


def normalized_key(value: str) -> str:
    return FORMAT.sub(ARG, value.replace("%%", "%"))


def catalog(name: str = "Localizable") -> dict:
    return json.loads((CATALOG_DIR / f"{name}.xcstrings").read_text())


def unit(entry: dict, language: str) -> str:
    return entry["localizations"][language]["stringUnit"]["value"]


def units(entry: dict, language: str) -> list[str]:
    """Return every rendered variant, including native String Catalog plurals."""
    output = []
    def visit(node: dict):
        if "stringUnit" in node:
            output.append(node["stringUnit"]["value"])
        for key, child in node.items():
            if key != "stringUnit" and isinstance(child, dict):
                visit(child)
    visit(entry["localizations"][language])
    if not output:
        raise KeyError("stringUnit or plural variations")
    return output


def protocol_reason(literal: Literal, source: str) -> str | None:
    if literal.value in RAW_ERROR_EXCEPTIONS.get(literal.path, set()):
        return "Stable validation/error contract; UI presents it through Api.displayError and the catalog."
    if literal.path == "Sources/MobileProductLifecycle.swift" and literal.value == "自检必须使用独立偏好域":
        return "DEBUG-only precondition protecting the isolated diagnostic preferences domain."
    if literal.path == "Sources/AccountSecurity.swift" and literal.value == "恒创联众":
        return "Configured SMS-provider brand name, explicitly excluded from translation."
    if literal.path == "Sources/PaperScanView.swift":
        if literal.value == "没读到做错的题":
            return "Backend recognition-log marker, parsed verbatim to preserve counts."
        start = source.find("    static func summary(")
        end = source.find("    static func displaySummary(")
        if start <= literal.start < end:
            return "Legacy summary is diagnostic output; UI uses localized displaySummary."
    if literal.path == "Sources/LessonWebView.swift":
        if "window.webkit.messageHandlers.edu.postMessage" in literal.value:
            return "Injected engine-probe JavaScript; Chinese appears only in its comment."
    return None


def swiftui_literal(literal: Literal, source: str) -> bool:
    # These overloads accept LocalizedStringKey directly. Deliberately reject
    # variable/ternary expressions, which often select the String overload.
    prefix = source[max(0, literal.start - 100):literal.start]
    return bool(re.search(
        r"(?:Text|Label|Button|Toggle|Picker|Stepper|Section|DisclosureGroup|TextField|SecureField|"
        r"navigationTitle|accessibilityLabel|configurationDisplayName|description)\s*\(\s*$", prefix))


def all_literals() -> list[Literal]:
    paths = sorted((ROOT / "Sources").glob("*.swift")) + sorted((ROOT / "Watch").rglob("*.swift"))
    return [literal for path in paths for literal in SwiftStrings(str(path.relative_to(ROOT)), path.read_text()).scan()]


def fixture_user_copy() -> list[dict[str, str]]:
    """Read exact synthetic user fields without starting/importing its server."""
    tree = ast.parse((ROOT / "scripts/demo/fixture.py").read_text())
    values = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        target = node.targets[0]
        if isinstance(target, ast.Name) and target.id in {"LESSONS", "WRONG"}:
            values[target.id] = ast.literal_eval(node.value)
        elif isinstance(target, ast.Tuple) and [item.id for item in target.elts] == ["USER", "NICK"]:
            values["NICK"] = ast.literal_eval(node.value)[1]
    output = [{"source": "fixture.nickname", "value": values["NICK"]}]
    for index, lesson in enumerate(values["LESSONS"]):
        output.extend(({"source": f"fixture.lessons[{index}].title", "value": lesson[1]},
                       {"source": f"fixture.lessons[{index}].unit", "value": lesson[4]}))
        output.extend({"source": f"fixture.lessons[{index}].questions[{number}]", "value": row[2]}
                      for number, row in enumerate(lesson[-1]))
    for slug, entries in values["WRONG"].items():
        output.extend({"source": f"fixture.review[{slug}][{index}].name", "value": row[1]}
                      for index, row in enumerate(entries))
    for node in ast.walk(tree):
        if isinstance(node, ast.Dict):
            for key, value in zip(node.keys, node.values):
                if isinstance(key, ast.Constant) and key.value == "desc" and isinstance(value, ast.Constant) and isinstance(value.value, str):
                    output.append({"source": "fixture.lesson.desc", "value": value.value})
    # These are complete brand names, not a bag of individually allowed characters.
    output.extend(({"source": "brand.name_zh", "value": "错题本"},
                   {"source": "brand.sms_sender", "value": "恒创联众"}))
    return output


def compact_text(value: str) -> str:
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", value))


def audit_han_line(text: str, allowed: list[dict[str, str]]) -> dict:
    """Allow exact user phrases or intact Chinese runs; never union their chars."""
    normalized = compact_text(text)
    matches = []
    for item in allowed:
        value = compact_text(item["value"])
        if len(normalized) >= 2 and normalized in value:
            return {"text": text, "residual_han": [], "allowed": [{**item, "match": normalized}]}
    remaining = normalized
    for item in sorted(allowed, key=lambda item: len(item["value"]), reverse=True):
        value = compact_text(item["value"])
        if value and value in remaining:
            matches.append({**item, "match": value})
            remaining = remaining.replace(value, "")
    fragments = [(fragment, item) for item in allowed for fragment in HAN_RUN.findall(item["value"]) if len(fragment) >= 2]
    for run in HAN_RUN.findall(remaining):
        match = next(((fragment, item) for fragment, item in fragments if len(run) >= 2 and run in fragment), None)
        if match:
            fragment, item = match
            matches.append({**item, "match": run, "fixture_fragment": fragment})
            remaining = remaining.replace(run, "")
    return {"text": text, "residual_han": HAN_RUN.findall(remaining), "allowed": matches}


class LocalizationTests(unittest.TestCase):
    def test_scanner_does_not_confuse_comments_or_nested_interpolation(self):
        source = '// "注释"\nText(String(localized: "还有 \\(n) 题"))\nText("漏译")\n'
        literals = SwiftStrings("fixture.swift", source).scan()
        self.assertEqual([(item.value, item.localized) for item in literals], [(f"还有 {ARG} 题", True), ("漏译", False)])
        self.assertEqual(format_args("%2$@ %1$lld"), format_args("%lld %@"))

    def test_ocr_user_data_exclusion_cannot_hide_interface_chinese(self):
        fixture = fixture_user_copy()
        self.assertIn({"source": "fixture.nickname", "value": "小林"}, fixture)
        self.assertTrue(any(item["source"] == "fixture.lesson.desc" for item in fixture))
        self.assertFalse(any(item["value"] in {"数学", "语文", "英语"} for item in fixture), "Canonical subject UI must be translated")
        allowed = [{"source": "fixture.question", "value": "把一个蛋糕平均分成 8 份，小林吃了 3 份"}]
        self.assertEqual(audit_han_line("8 份，小林吃了", allowed)["residual_han"], [])
        self.assertEqual(audit_han_line("Review · 把一个蛋糕平均分成", allowed)["residual_han"], [])
        self.assertEqual(audit_han_line("复习 · 把一个蛋糕平均分成", allowed)["residual_han"], ["复习"])
        self.assertEqual(audit_han_line("吃分", allowed)["residual_han"], ["吃分"])

    def test_main_views_have_no_unlocalized_bundled_chinese(self):
        missing = []
        for path in UI_FILES:
            source = (ROOT / path).read_text()
            for literal in SwiftStrings(path, source).scan():
                if HAN.search(literal.value) and not literal.localized and not swiftui_literal(literal, source) and not protocol_reason(literal, source):
                    missing.append(f"{path}:{literal.line}: {literal.value[:100]}")
        self.assertFalse(missing, "Unlocalized UI copy:\n" + "\n".join(missing))

    def test_every_localized_swift_key_exists_in_catalog(self):
        keys = {normalized_key(key) for key in catalog()["strings"]}
        missing = []
        for item in all_literals():
            source = (ROOT / item.path).read_text()
            bundled_key = item.localized or (HAN.search(item.value) and swiftui_literal(item, source))
            raw_error = item.value in RAW_ERROR_EXCEPTIONS.get(item.path, set())
            if (bundled_key or raw_error) and item.value not in keys:
                missing.append(f"{item.path}:{item.line}: {item.value}")
        self.assertFalse(missing, "Missing String Catalog keys:\n" + "\n".join(missing))

    def test_recognition_diagnostics_keep_their_original_language_contract(self):
        source = (ROOT / "Sources/PaperScanView.swift").read_text()
        diagnostic = source[source.index("    static func summary("):source.index("    static func displaySummary(")]
        self.assertNotIn("String(localized:", diagnostic)
        self.assertIn('return "跑完了，详情见读图记录"', diagnostic)
        self.assertIn(".done(Self.displaySummary(log, got: g, skipped: k))", source)
        self.assertIn("PaperScanView.summary(log, got: g, skipped: k)", (ROOT / "Sources/PaperScan.swift").read_text())

    def test_english_and_chinese_entries_and_placeholders(self):
        failures = []
        for name in ("Localizable", "InfoPlist"):
            data = catalog(name)
            self.assertEqual(data["sourceLanguage"], "en", name)
            for key, entry in data["strings"].items():
                try:
                    english_variants, chinese_variants = units(entry, "en"), units(entry, "zh-Hans")
                except KeyError as error:
                    failures.append(f"{name}: {key!r}: missing {error}")
                    continue
                for language, variants in (("en", english_variants), ("zh-Hans", chinese_variants)):
                    for value in variants:
                        if not value.strip():
                            failures.append(f"{name}: {key!r}: empty {language} translation")
                        if language == "en" and HAN.search(value):
                            failures.append(f"{name}: {key!r}: Chinese remains in English")
                        if format_args(value) != format_args(chinese_variants[0]):
                            failures.append(f"{name}: {key!r}: placeholder mismatch")
                        if name == "Localizable" and format_args(key) != format_args(value):
                            failures.append(f"{name}: {key!r}: source placeholder mismatch")
        self.assertFalse(failures, "\n".join(failures))

    def test_development_language_bundle_languages_and_target_resources(self):
        project = yaml.safe_load((ROOT / "project.yml").read_text())
        base = project.get("settings", {}).get("base", {})
        development = project.get("options", {}).get("developmentLanguage", base.get("DEVELOPMENT_LANGUAGE"))
        self.assertEqual(development, "en")
        for name in ("WrongBook", "WrongBookWatch", "WrongBookWatchWidget"):
            target = project["targets"][name]
            settings = {**base, **target.get("settings", {}).get("base", {})}
            info = target.get("info", {}).get("properties", {})
            languages = info.get("CFBundleLocalizations", settings.get("INFOPLIST_KEY_CFBundleLocalizations", []))
            if isinstance(languages, str):
                languages = languages.replace(",", " ").split()
            self.assertTrue({"en", "zh-Hans"}.issubset(languages), name)
            for filename in ("Localizable.xcstrings", "InfoPlist.xcstrings"):
                resource = CATALOG_DIR / filename
                matches = []
                for entry in target.get("sources", []) + target.get("resources", []):
                    entry = {"path": entry} if isinstance(entry, str) else entry
                    candidate = ROOT / entry.get("path", "")
                    if candidate == resource or candidate in resource.parents:
                        matches.append(entry)
                self.assertTrue(matches, f"{name} must compile {filename}")
                self.assertTrue(any(item.get("type") != "folder" for item in matches),
                                f"{name} must compile its String Catalog, not copy it as a folder")

    def test_permission_usage_strings_are_localized(self):
        entries = catalog("InfoPlist")["strings"]
        for key in ("CFBundleDisplayName", "NSCameraUsageDescription", "NSPhotoLibraryUsageDescription"):
            self.assertIn(key, entries)
            self.assertTrue(unit(entries[key], "en"))
            self.assertTrue(unit(entries[key], "zh-Hans"))

    def test_rendered_english_views_have_no_non_user_chinese(self):
        receipt = Path(os.environ.get("WRONGBOOK_L10N_RESULT", ROOT / "perf/acceptance/l10n/result.json")).expanduser().resolve()
        if not receipt.is_file():
            self.skipTest(f"截图待队列续跑：尚无 captured 截图回执（{receipt}）")
        result = json.loads(receipt.read_text())
        if result.get("status") in {None, "running", "deferred", "blocked"}:
            self.skipTest("截图待队列续跑：" + str(result.get("detail") or result.get("status")))
        self.assertEqual(result.get("status"), "captured", "Screenshot capture failed: " + str(result.get("detail")))
        self.assertTrue(result.get("source_unchanged_during_capture"), "Screenshots must bind unchanged source inputs")
        args = result.get("language_arguments", {}).get("en", [])
        for flag, value in (("-AppleLanguages", "(en)"), ("-AppleLocale", "en_US")):
            self.assertIn(flag, args)
            self.assertEqual(args[args.index(flag) + 1], value)
        fixture_sha = hashlib.sha256((ROOT / "scripts/demo/fixture.py").read_bytes()).hexdigest()
        self.assertEqual(result.get("fixture_source_sha256"), fixture_sha, "OCR exclusions must use the captured fixture version")
        allowed = fixture_user_copy()
        report = {"receipt": str(receipt), "fixture_source_sha256": fixture_sha, "language": "en",
                  "allowed_user_data": allowed, "screens": {}, "status": "checking"}
        failures, unavailable = [], []
        screens = result.get("screens", {}).get("en", {})
        for name in ("login", "library", "import", "review"):
            self.assertIn(name, screens, f"Missing English screenshot: {name}")
            shot = screens[name]
            self.assertEqual(shot.get("language"), "en", name)
            self.assertEqual(shot.get("locale"), "en_US", name)
            self.assertEqual(shot.get("language_arguments"), args, "Each screenshot must retain its actual language launch arguments")
            image = Path(shot["path"])
            image = image if image.is_absolute() else receipt.parent / image
            self.assertTrue(image.is_file(), str(image))
            self.assertEqual(hashlib.sha256(image.read_bytes()).hexdigest(), shot["sha256"], name)
            ocr = shot.get("ocr", {})
            rows = []
            if ocr.get("status") != "captured" or not ocr.get("lines"):
                unavailable.append(name + ": " + str(ocr.get("reason") or "OCR text is unavailable"))
            for row in ocr.get("lines", []):
                self.assertIsInstance(row, dict, "OCR must preserve the original text/box row")
                checked = audit_han_line(str(row.get("t", "")), allowed)
                rows.append({"ocr": row, **checked})
                if checked["residual_han"]:
                    failures.append(f"{name}: {checked['text']} (untranslated: {checked['residual_han']})")
            report["screens"][name] = {"path": str(image), "ocr_status": ocr.get("status"), "rows": rows}
        report.update(status="unavailable" if unavailable else ("failed" if failures else "passed"),
                      unavailable=unavailable, failures=failures,
                      manual_review="All original OCR rows are retained; text truncation and layout still require visual review.")
        output = receipt.with_name("ocr-english-check.json")
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        if unavailable:
            self.skipTest("OCR 待队列续跑：" + "; ".join(unavailable) + f"；原始OCR行：{output}")
        self.assertFalse(failures, f"Untranslated rendered English UI ({output}):\n" + "\n".join(failures))


if __name__ == "__main__":
    unittest.main()
