# StillOpen

A local-first, phone-first Flutter app for keeping loose ends visible until handled: capture notes and attachments, organize open and waiting items, complete or reopen them, set reminders, use recurring cycles, and export/import local backups.

Experimental and unmaintained; looking for a maintainer. Independent forks are welcome. There is no support or review commitment. This Android-focused source prerelease includes no app binaries.

## Scope

Android-focused source prerelease. Flutter implementation, Android host, synthetic tests and share-sender fixture are included. iOS native hosts, web/desktop shells, legacy prototypes, historical evidence and the developer gateway are omitted. No hosted API, account, cloud deployment or paid service is required. Physical-device behavior and iOS are unverified.

## Developer start

Use Flutter **3.44.1** (Dart **3.12.1**), Java **17**, and the Android SDK with platform **36**, build tools 36.0.0 and NDK 28.2.13676358. Dependency resolution and the first Android build need network access to public package repositories and may exceed ten minutes.

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
# On an explicitly selected disposable Android emulator:
flutter run --debug -d <emulator-serial>
```

The Gradle 9.1.0 wrapper is included from its official source and its distribution checksum is pinned. No signing keys, secrets file, external checkout or deployment runner is needed. The debug APK is local test output, never a distributed release artifact. See [build and test evidence](docs/BUILD_AND_TEST.md).

## Structure and privacy

`lib/main.dart` contains the UI; `lib/src/controller.dart` manages lifecycle/persistence. Models, date and recurrence rules, attachments, incoming shares and reminders live under `lib/src/`. `test/` covers controllers, rules, migration, backup and widgets; `integration_test/` exercises native preferences. Fixtures are synthetic.

Items use local SharedPreferences and ordinary app files. There is no app-level encrypted store. Backups can contain titles and attachment bytes; exported files and shares leave the app's private storage. Reminder notifications may reveal titles on the lock screen. Android scheduling can be delayed by the OS. The app has no observed account/network client; plugins and files opened outside the app have their own behavior. No runtime traffic audit was performed.

## Limits and licensing

No app-store readiness, physical delivery, camera/provider, OEM sharing or iOS parity claim is made. Analyzer, 183 unit/widget tests and an Android debug build passed. Native smoke results and remaining limits are recorded in the build guide. Original artwork is replaced with simple code/vector placeholders.

First-party software and tests are licensed under [MIT](LICENSE). [Third-party notices](THIRD_PARTY_NOTICES.md) describe separately licensed tooling and dependencies and do not confer rights to the app.
