# StillOpen

### Make room for what matters. Keep track of what isn't finished.

The message you meant to answer. The document you need to send. The thing you promised yourself you'd come back to.

Small unfinished things have a way of taking up more space in your head than they deserve.

**StillOpen gives them somewhere else to live.**

A quiet, local-first Android app for capturing loose ends, keeping them visible, and finally closing them. No account, no cloud service to maintain, no productivity theater. Just a place to remember what is still open.

---

## Capture it. Find it. Finish it.

- **Catch the thought.** Save quick notes and attachments before they disappear.
- **See what's waiting.** Keep open and waiting items together instead of scattered across apps and memory.
- **Close the loop.** Mark things done, or reopen them when life changes.
- **Handle what repeats.** Use recurring cycles for obligations that don't stay finished forever.
- **Remember at the right time.** Set local reminders.
- **Keep your data yours.** Work locally and export or import backups when you need to move your information.

> **The idea:** You shouldn't have to keep remembering something just because it isn't finished.

## Why open source?

StillOpen began as a personal software project. The application works, but maintaining a commercial product and navigating app-store distribution aren't the goal.

So the source is here instead: **to be explored, adapted, improved, or taken further by someone else.**

If the idea resonates, fork it. Build your own version. Make it better. A new maintainer is welcome to carry it forward.

**Project status:** Experimental and unmaintained. There is no guaranteed support, review, security update, or future release. This repository is an **Android-focused source prerelease**, not a packaged app-store download.

## Built to be straightforward

| | |
| --- | --- |
| **Platform** | Flutter / Dart, Android host |
| **Data** | Local preferences and application files |
| **Accounts** | None required |
| **Hosted backend** | None required |
| **Source license** | [MIT](LICENSE) for first-party code and tests |
| **Release** | [Experimental source prerelease](../../releases/tag/v1.0.0-oss.1) |

The repository includes the Flutter application, Android host, automated tests, synthetic fixtures, dependency lockfile, build instructions, and [third-party notices](THIRD_PARTY_NOTICES.md). It intentionally excludes the iOS host, web/desktop shells, legacy prototypes, developer gateway, and private development history.

## Build it yourself

You'll need Flutter **3.44.1** (Dart **3.12.1**), Java **17**, and the Android SDK with platform **36**, build tools **36.0.0**, and NDK **28.2.13676358**.

```bash
git clone https://github.com/jedufa/stillopen.git
cd stillopen
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

To launch the app, select an Android emulator and run `flutter run --debug -d <emulator-serial>`.

The first build downloads dependencies and may take a while. The debug APK is development output, **not** a signed production release. For details, see [Build and test](docs/BUILD_AND_TEST.md).

## What has been verified?

The source release passed static analysis, **183 unit/widget tests**, and an Android debug build. Disposable-emulator checks exercised capturing, completing and reopening items, recurring cycles, backup/restore through the controller, and persistence across a restart.

It has **not** been verified on physical devices or qualified for an app store. Actual notification delivery, device-specific sharing, camera/provider flows, native backup pickers, and iOS behavior remain unverified.

## A note on privacy

Local-first doesn't mean encrypted. StillOpen stores information in ordinary app preferences and files. Exported backups and shared attachments can expose their contents; reminder titles may appear on a lock screen. Treat sensitive material accordingly. No runtime network-traffic audit has been performed. See [Security](SECURITY.md).

---

### Some things are worth remembering. Not all of them belong in your head.

**StillOpen is open for someone to take further.** [Explore the code](lib/) · [Read the build guide](docs/BUILD_AND_TEST.md) · [See the license](LICENSE)

<sub>Copyright © 2026 Jean-Francois Dufour. First-party code licensed under MIT; third-party materials retain their own terms.</sub>
