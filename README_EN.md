[中文](README.md) | **English**

<p align="center"><img src="Resources/icon-1024.png" width="96" alt="Mistake Notebook"></p>

# Mistake Notebook · 错题本



**Organize your mistakes so you can answer with more confidence next time.**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B%20·%20macOS%2015.0%2B-000?logo=apple) [![App Store](https://img.shields.io/badge/App%20Store-available-0D84FF?logo=apple)](https://apps.apple.com/app/id6806626967) ![License](https://img.shields.io/badge/License-MIT-green)

Start with your own exam papers and photos of missed questions, organizing scattered study materials for ongoing review. New accounts and public installers start with an empty personal notebook; study materials and records are isolated by account.

The three entry points are Notebook, Import, and Review, with account, reminders, and offline management in Settings at the top right. iPhone / iPad use the regular camera or photo library; Mac selects image files. After upload confirmation, the shared learning-library service recognizes the content. Practice and review use your own questions; similar variants are not promised for every question.


## What it does

| Feature | Description |
|---|---|
| **Organize your own mistakes** | Import photos of your missed questions to build personal study materials. New accounts start empty. |
| **Download your own practice for offline review** | Sign in to sync your materials; downloaded practice works offline. Study records are stored separately for each account. |
| **Import by taking or selecting photos** | Phones and tablets can take photos or choose from the library; Mac selects image files. Confirm subject, page numbers, and the AI-recognition notice before upload, then upload page by page and inspect results. The first 10 images per account are free; afterward, choose an Apple monthly or annual subscription to continue recognition. No invitation code or API key is needed. |

## Availability

Available on the [App Store](https://apps.apple.com/app/id6806626967): 1.0 (build 18) has been on sale since 2026-09-15; see the [release record](perf/asc-release.json).

The public package includes no personal courses or question bank. Users import their own practice materials; sync-lessons.sh maintains only the zero-course public package.

## Command line for agents · `mistakes`

The app is for people; the command line is for agents. `cli/mistakes` is a thin client of the same server the app and the website use (the `/api/*` endpoints of `edu.tianli.cyou`), written with the Python standard library only. Upload size, recognition quota, subscriptions, account ownership and the deletion freeze are all decided on the server, and recognition and practice generation run in the same server-side worker.

A locally built Mac edition carries the command at `错题本.app/Contents/Resources/bin/mistakes` (a `project.yml` build phase copies it only in macOS builds, before signing); iPhone/iPad packages and every archive (App Store / TestFlight) leave it out.

```bash
sh cli/install.sh          # Mac edition installed: finds the .app by bundle id and links to the command inside it; otherwise links to cli/mistakes in this repo (source edits apply at once)
sh cli/install.sh --check  # verify only; --uninstall removes only this product's link
```

If the installed Mac edition is an older build without the command, `install.sh` refuses and asks for a reinstall of the Mac edition instead of falling back to the repo.

Credentials come only from environment variables or stdin and are never stored or echoed: `EDU_USER` (email or username), `EDU_PASSWORD` (or `--password-stdin`); `EDU_API_BASE` defaults to `https://edu.tianli.cyou`.

```bash
mistakes status --json                         # recognition quota/subscription, pending photos and papers, running jobs, deletion state
mistakes wrongs --subject math --json          # the mistake notebook (server snapshot of the practice archive, grouped by lesson)
mistakes progress --json                       # questions done today, daily goal, XP, streak
mistakes import p1.jpg p2.jpg --year 2026 --term 1 --grade 3 --subject math --kind final --consent-ai --wait 120
mistakes job <job-id> --wait 60 --json
mistakes delete upload <photo-id> --yes
```

Every read command supports `--json` and prints `{"ok": true, …}`; failures print `{"ok": false, "err": …}` and exit non-zero (1 = refused by the server, network failure or failed job; 2 = usage error or missing credentials). Read commands never change state. Commands that send images to AI recognition and use quota (`upload`, `import`, `recognize --kind auto|draft`) require `--consent-ai`, matching the app's consent step; deletions require `--yes`.

| In the app | Command |
|---|---|
| Account, AI quota and subscription state, deletion progress in Settings | `mistakes status` / `mistakes account deletion-status [--receipt ID]` |
| Mistake notebook / review (by lesson, by subject, search) | `mistakes wrongs [--subject] [--search]` |
| Today's goal, XP, streak | `mistakes progress` |
| Personal lesson pack / download one lesson | `mistakes lessons` / `mistakes lesson <slug> --out FILE` |
| Import a paper (page-by-page upload, automatic recognition) | `mistakes import <images…> --slug or --year --term --grade --subject --kind` |
| Single mistake photo, queue recognition or commit to the personal lesson pack | `mistakes upload` / `mistakes recognize <photo-id> --kind auto\|draft\|commit` |
| Upload history and job progress | `mistakes uploads` / `mistakes papers` / `mistakes job <job-id> [--wait SECONDS]` |
| View an uploaded original photo / paper page | `mistakes image upload <photo-id>` / `mistakes image paper <slug> --page N` |
| Delete an upload | `mistakes delete upload\|paper <id> --yes` |
| Delete the account (immediate deletion first, a deletion request when scan history exists) | `mistakes account delete --yes` |

Note: `wrongs` and `progress` read the server snapshot of the practice archive (synced by the practice pages while a device is online, last write wins), so work done offline appears after the next sync; the app's notebook also shows the original question rows from the lesson pack, while the command line lists the mistake types stored in the archive.

GUI-only (pure interface or device-only): taking or picking photos, page previews, answering practice questions, daily reminders, offline lesson copies, and buying or restoring the Apple subscription (the server only trusts Apple-signed transactions).

Regression: `python3 Tests/cli_mistakes_test.py` first checks the packaging rule and `install.sh` (a fake .app in a temporary Applications folder), then starts an isolated local server (temporary directory, free port), never touches live accounts and never calls the AI; it needs `edu/web/points/server.py` from the same workspace, or `EDU_SERVER_PY` pointing to it.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme WrongBook -destination 'generic/platform=iOS Simulator' build
```

- The repository's `*.sh` files are shims for the author's local fleet scripts (three-platform builds / device installation / TestFlight). They depend on HQ tools under `~/Dev` that are not in this repository; without them, the scripts exit explicitly.
- `Shared/PlatformCompat.swift` is a byte-for-byte copy of a shared HQ file (iOS-only SwiftUI modifiers become same-named no-ops on macOS). Do not edit it here.
- The preBuildScripts in `project.yml` run `sync-lessons.sh` to generate and validate an empty personal manifest with zero courses, without accessing the author's private content library.

See [DEVELOPING.md](DEVELOPING.md) for development details, including regression checks, validation channels, and constraints.

## Related

- Product page: <https://apps.tianli.cyou/p/wrong-book-ios.html>
- Fleet overview (how the 10 apps came about): <https://apps.tianli.cyou/ios.html>
- Tutorial: [From zero to TestFlight: the complete path to building iPhone apps solo](https://blog-ai.tianli.cyou/nine-ios-apps-in-two-weeks)

## License

MIT © 2026 Tianli Zeng

<!-- lightweight:start -->
## Resource use

Download size is App Store data; memory, CPU and launch time are iOS Simulator measurements, not physical-device figures.

| Download | Idle memory | Idle CPU | Simulator cold launch to first screen ready |
|---|---|---|---|
| **2.2 MB** (installed 3.0 MB) | **24.1 MB** | **0.02%** | **1.4 s** |

Sizes are read back for this exact distribution build. The physical device is not yet measured, so memory, CPU and launch time come from the iOS Simulator and are labelled as such.

<sub>v1.0 (18) · iPhone 17（iPhone18,3）；体积为 Apple 设备切片记录，运行性能尚未真机实测 · App Store; package sizes exclude user data and caches; installed phone version not verified · measured 2026-09-26. Sizes come from Apple App Store Connect device slices for this build. Memory, CPU and launch time were measured on iPhone 17 Pro / iOS 27.0 Simulator / Mac16,12 / Apple M4 / macOS 27.2 with a local Release build v1.0 (11) (2026-09-27), App process only; these are not physical-device figures, which are still unmeasured. Memory uses phys_footprint; CPU is CPU time ÷ wall time over a 60-second sampling window; sizes in decimal MB. Raw data: [perf/lightweight.json](perf/lightweight.json).</sub>
<!-- lightweight:end -->
