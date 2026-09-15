[中文](README.md) | **English**

<p align="center"><img src="Resources/icon-1024.png" width="96" alt="Mistake Notebook"></p>

# Mistake Notebook · wrong-book



**Organize your mistakes so you can answer with more confidence next time.**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B%20·%20macOS%2015.0%2B-000?logo=apple) ![TestFlight](https://img.shields.io/badge/TestFlight-内测中-0D84FF) ![License](https://img.shields.io/badge/License-MIT-green)

Start with your own exam papers and photos of missed questions, organizing scattered study materials for ongoing review. New accounts and public installers start with an empty personal notebook; study materials and records are isolated by account.

The three entry points are Notebook, Import, and Review, with account, reminders, and offline management in Settings at the top right. iPhone / iPad use the regular camera or photo library; Mac selects image files. After upload confirmation, the shared learning-library service recognizes the content. Practice and review use your own questions; similar variants are not promised for every question.


## What it does

| Feature | Description |
|---|---|
| **Organize your own mistakes** | Import photos of your missed questions to build personal study materials. New accounts start empty. |
| **Download your own practice for offline review** | Sign in to sync your materials; downloaded practice works offline. Study records are stored separately for each account. |
| **Import by taking or selecting photos** | Phones and tablets can take photos or choose from the library; Mac selects image files. Confirm subject, page numbers, and the AI-recognition notice before upload, then upload page by page and inspect results. The first 10 images per account are free; afterward, choose an Apple monthly or annual subscription to continue recognition. No invitation code or API key is needed. |

## Availability

In private TestFlight testing; no public link is available yet.

The public package includes no personal courses or question bank. Users import their own practice materials; sync-lessons.sh maintains only the zero-course public package.

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
