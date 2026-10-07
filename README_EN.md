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

## One app, five platforms

Same name, same icon, same study library: iPhone, iPad, Mac and Apple Vision Pro are one target, and Apple Watch is a watch app installed along with the iPhone package. Mistakes and progress live on the server, so practice done on one device shows on the others after a sync.

| Platform | What it looks like | Can you install it now |
|---|---|---|
| iPhone | Three tabs (mistakes / review / import); import by taking or choosing photos | On the [App Store](https://apps.apple.com/app/id6806626967) |
| iPad | Wide layout: sidebar (mistakes / review / import + today's progress) + mistake list + question side by side; a narrow Split View falls back to the iPhone layout | The package on sale is the same one, but **this wide layout is not released yet** |
| Mac | Native macOS window with the same three columns; import through a file dialog; the package bundles the `mistakes` CLI | **Not released**, local builds only |
| Apple Watch | Raise your wrist for how many categories need review, today's count and the streak; swipe for what to review first; four complications. Read-only: no practice, no import; the sign-in is handed over from the iPhone | **Not released** (the watch app embedded in the iPhone package is not in any release build yet) |
| Apple Vision Pro | The same three columns in a system glass window; no camera, so import picks image files | **Not released**, verified on the simulator only |

<table><tr>
<td align="center" width="50%"><img src="docs/screenshots/07-ipad.png" alt="iPad landscape: sidebar, mistake list and question side by side"><br><sub>iPad landscape: sidebar, mistake list and question side by side (simulator screenshot)</sub></td>
<td align="center" width="50%"><img src="docs/screenshots/08-mac.png" alt="Mac: mistake list and question side by side"><br><sub>Mac: mistake list and question side by side (quiet offscreen capture on this Mac; sidebar cropped because offscreen rendering cannot draw the selected row's system material)</sub></td>
</tr><tr>
<td align="center" width="50%"><img src="docs/screenshots/10-vision.png" alt="Apple Vision Pro: the mistake notebook in a glass window"><br><sub>Apple Vision Pro: the mistake notebook in a glass window (simulator screenshot, cropped)</sub></td>
<td align="center" width="50%"><img src="docs/screenshots/09-watch.png" width="208" alt="Apple Watch: categories to review, today's count and streak"><br><sub>Apple Watch: categories to review, today's count and streak (simulator screenshot)</sub></td>
</tr></table>

The account "小林", the five practice sets and the mistake records in the screenshots are demo data (a fictional study library that `scripts/demo/fixture.py` starts locally), not any real student's records.

### Per-platform resource use (simulator and native measurements)

<!-- platforms:start -->
| Platform | Measured on | Package (zip) | Idle memory | Idle CPU | Cold launch to first data screen | Host load (1 / 5 / 15 min) | Target |
|---|---|---|---|---|---|---|---|
| iPhone | not measured | — | — | — | — | — | ≤ 150 MB · ≤ 0.5% |
| iPad | not measured | — | — | — | — | — | ≤ 150 MB · ≤ 0.5% |
| Mac | not measured | — | — | — | — | — | ≤ 150 MB · ≤ 0.5% |
| Apple Watch | not measured | — | — | — | — | — | ≤ 25 MB · ≤ 10 MB package · ≤ 1.5 s |
| Apple Vision Pro | not measured | — | — | — | — | — | ≤ 60 MB |

<sub>Measured ; data in `perf/platforms/<platform>.json`. iPhone, iPad, Watch and Vision are Release builds on Xcode simulators, the Mac is a native local Release build; **none of these are real-device numbers, and the package sizes are not App Store slices** (the App Store iPhone size is under "Resource usage" below). Memory is the app process's phys_footprint; CPU is CPU time ÷ wall time over 60 s after a 45 s settle; cold launch is the median time from the launch request to the app's "first data-bearing screen" log (fictional local demo library, 5 runs, the first run after install discarded). Simulator launch times swing widely with host load: with memory tight on 2026-10-02, the same code on the Growth Treasury iPhone lane measured 1.8–4.1 s at different times. Most of a Vision Pro cold launch is the simulator's own overhead (process spawn, visionOS scene setup), which stretches noticeably on a busy host.</sub>
<!-- platforms:end -->

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
mistakes version --json                        # no sign-in: CLI and containing app version, server reachable or not, credentials present or not
mistakes status --json                         # recognition quota/subscription, pending photos and papers, running jobs, deletion state
mistakes questions --pending --json            # notebook / review list: original question rows from the lesson pack, here only those still to review
mistakes wrongs --subject math --json          # mistake types in the archive (server snapshot of the practice archive, grouped by lesson)
mistakes progress --json                       # questions done today, daily goal, XP, streak
mistakes import p1.jpg p2.jpg --year 2026 --term 1 --grade 3 --subject math --kind final --consent-ai --wait 120
mistakes job <job-id> --wait 60 --json
mistakes delete upload <photo-id> --yes
```

Every read command supports `--json` and prints `{"ok": true, …}`; failures print `{"ok": false, "err": …}` and exit non-zero (1 = refused by the server, network failure or failed job; 2 = usage error or missing credentials); failures also carry `error: {code, message}` (`usage` / `rejected` / `failed`), and a mistyped argument with `--json` prints the same shape. `mistakes --help` lists every read and write command, the exit-code table and the window-only items. Read commands never change state. Commands that send images to AI recognition and use quota (`upload`, `import`, `recognize --kind auto|draft`) require `--consent-ai`, matching the app's consent step; deletions require `--yes`.

| In the app | Command |
|---|---|
| Account, AI quota and subscription state, deletion progress in Settings | `mistakes status` / `mistakes account deletion-status [--receipt ID]` |
| Mistake notebook / review list (one row per original question, by subject, to-review only, search) | `mistakes questions [--subject] [--pending] [--search]` |
| Mistake types with wrong and corrected counts (same source as the watch's "review first") | `mistakes wrongs [--subject] [--search]` |
| Today's goal, XP, streak | `mistakes progress` |
| Personal lesson pack / download one lesson | `mistakes lessons` / `mistakes lesson <slug> --out FILE` |
| Import a paper (page-by-page upload, automatic recognition) | `mistakes import <images…> --slug or --year --term --grade --subject --kind` |
| Single mistake photo, queue recognition or commit to the personal lesson pack | `mistakes upload` / `mistakes recognize <photo-id> --kind auto\|draft\|commit` |
| Upload history and job progress | `mistakes uploads` / `mistakes papers` / `mistakes job <job-id> [--wait SECONDS]` |
| View an uploaded original photo / paper page | `mistakes image upload <photo-id>` / `mistakes image paper <slug> --page N` |
| Delete an upload | `mistakes delete upload\|paper <id> --yes` |
| Delete the account (immediate deletion first, a deletion request when scan history exists) | `mistakes account delete --yes` |
| Mac edition, Settings and Updates: iCloud settings switch and sync status, export / import settings, daily reminder switch and hour | `mistakes config status` / `config export -o FILE` / `config import FILE --yes` / `config sync on\|off --yes` |
| Mac edition: sync mistakes, check the offline lessons now / disable the local lesson copy | `mistakes offline sync` / `mistakes offline reset --yes` |
| Mac edition: sign out | `mistakes app logout --yes` |
| Mac edition: check for updates / upgrade (verifies the release package and reports where it is) | `mistakes update check` / `mistakes update install --yes` |

Note: `wrongs` and `progress` read the server snapshot of the practice archive (synced by the practice pages while a device is online, last write wins), so work done offline appears after the next sync; `questions` reads the lesson pack from the server and lists the same original question rows as the app's notebook (no answers or options), marking those still to review from the archive; `wrongs` lists only the mistake types stored in the archive.

GUI-only (pure interface or needs a person): taking photos (use `import` for existing image files; argument order is page order), page previews, answering practice questions, buying or restoring the Apple subscription (the server only trusts Apple-signed transactions), browsing without signing in, choosing the iCloud Drive update folder on the Mac, the policy and support links, and placing watch complications. The "Mac edition" rows act on this Mac's own app settings, offline copy and session: the Mac app's own executable runs them (no window, no account password), and the command handles the export and import files; to change the daily reminder, export, edit `defaults.remind_enabled` and `defaults.remind_hour`, and import. The sandboxed Mac edition cannot replace itself, so `update install` verifies the release package (identity, size, SHA256) and reports where it is; checking for updates needs the iCloud Drive update folder to have been chosen once in the app. The same items on iPhone / iPad / Vision Pro live only on that device and no command can reach them. See `mistakes config --help`. Email registration, email verification and change, email recovery and changing an existing password use `treasury account` on the same backend.

Regression: `python3 Tests/cli_mistakes_test.py` first checks the packaging rule and `install.sh` (a fake .app in a temporary Applications folder), then starts an isolated local server (temporary directory, free port), never touches live accounts and never calls the AI; it needs `edu/web/points/server.py` from the same workspace, or `EDU_SERVER_PY` pointing to it.

The 2026-10-06 source adds phone accounts: SMS login, phone registration and phone/email password recovery on the login screen; phone binding or two-number replacement, email verification, and password setup/change under Settings → Account and Privacy. Existing users should sign in first and bind a number to preserve the original internal account, mistakes and subscription. Phone registration creates an empty personal library. SMS currently supports an adult's own mainland China +86 number; email remains available for other regions. The client only calls the shared education service and contains no Alibaba Cloud credentials. Real delivery and the complete native cross-device flow for this source remain unverified; isolated tests are not delivery evidence.

`mistakes account phone-login --phone <number>`, `phone-register --phone <number> --agreed`, and `phone-recover --phone <number>` work without a prior password session. Existing users run `mistakes account phone-bind --phone <new-number>` with their original login; replacement verifies both numbers. Passwordless phone users can start this process's session with `--sms-phone <number>` and run `account password-set`. Codes and new passwords use hidden interactive input or protected environment variables `EDU_SMS_CODE`, `EDU_SMS_OLD_CODE`, `EDU_SMS_IDENTITY_CODE`, and `EDU_NEW_PASSWORD`, never command arguments. Independent-email risk verification supports `--risk-email` and `EDU_EMAIL_CODE`. After an uncertain send, resume the returned `request_id` with `--request-id`; the client never automatically resends. Cookies only live in this process; a login command does not persist a session for other processes.

SMS CLI contract checks: `python3 Tests/cli_phone_test.py` (9 loopback cases, no real messages). Work follows the shared `aliyun-sms` skill. Project boundaries and remaining real-flow validation are recorded locally in `handoffs/2026-10-06-sms-account.md`, which is internal and not published with this repository.

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

| Download | Idle memory | Idle CPU | Simulator cold launch to first data-bearing screen |
|---|---|---|---|
| **2.2 MB** (installed 3.0 MB) | **37.7 MB** | **0.03%** | **2.4 s** |

Sizes are read back for this exact distribution build. The physical device is not yet measured, so memory, CPU and launch time come from the iOS Simulator and are labelled as such.

<sub>v1.0 (18) · iPhone 17（iPhone18,3）；体积为 Apple 设备切片记录，运行性能尚未真机实测 · App Store; package sizes exclude user data and caches; installed phone version not verified · measured 2026-09-26. Sizes come from Apple App Store Connect device slices for this build. Memory, CPU and launch time were measured on iPhone 17 Pro (iPhone-17-Pro) / iOS 27.0 Simulator with a local Release build v1.0.1 (19) (2026-10-06), App process only; these are not physical-device figures, which are still unmeasured. Memory uses phys_footprint; CPU is CPU time ÷ wall time over a 60-second sampling window; sizes in decimal MB. Raw data: [perf/lightweight.json](perf/lightweight.json).</sub>
<!-- lightweight:end -->


## Configuration and app updates

New builds include a “Configuration and Updates” button below the main interface. The installed version and build come from the app bundle.

Settings sync is optional and off by default. It transfers the daily reminder switch and hour. Settings can be exported as JSON and imported from Files. Restoring settings reschedules local reminders without asking for notification permission; study materials keep their existing account sync.

The iPhone and iPad update check reads the App Store release and opens this app's system store page. Network failures remain visible. App-version checking is separate from refreshing study materials or backend data.

A source version bump does not mean a new phone build has already been distributed; release and installation records identify the available build.

The sandboxed Mac target uses provisioned iCloud KVS for the same settings allowlist. Mac updates come from private packages in the owner's iCloud Drive. Select the system iCloud Drive root once in “Choose iCloud Drive Update Folder”; its security bookmark stays on this Mac. After a real release is available, open its verified ZIP and move the app into Applications to upgrade. Directory permissions and update packages are excluded from synced settings.
