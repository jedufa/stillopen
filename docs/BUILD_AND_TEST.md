# Build and test

Android-focused experimental source prerelease. First-party code and tests are MIT licensed. Validation below describes this source snapshot; no app binary or app-store release is provided.

## Verified toolchain and newcomer path

Flutter 3.44.1 (framework revision `924134a44c189315be2148659913dda1671cbe99`), Dart 3.12.1, Temurin Java 17.0.18, Android SDK platform 36, build tools 36.0.0 and NDK 28.2.13676358. The included Gradle 9.1.0 wrapper has verified upstream bytes and a pinned distribution checksum.

From the repository root, with Flutter/Java/Android SDK installed:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --reporter json
flutter build apk --debug --no-pub
```

Preparation started with empty run-owned Pub and Gradle caches and an isolated HOME. Fresh clean-room clones reused only those newly populated caches; no preexisting host Pub/Gradle cache, project-server checkout or secrets were used. The installed Flutter SDK, Java and Android SDK were shared permitted toolchains. Exact locked resolution passed without lockfile changes. Analyzer reported no issues. All 183 unit/widget tests passed with zero skipped tests. Android debug build passed; its first download of a Flutter engine artifact failed with a transport tag mismatch, then Flutter's automatic retry succeeded. Network setup may exceed ten minutes.

The pinned build reports Kotlin Gradle Plugin compatibility warnings for the app and five plugins. Future Flutter upgrades require renewed validation and may require migration to built-in Kotlin. No dependency upgrade is included here. No release signing or APK publication occurred.

## Runtime evidence

A fresh disposable Android 15 / API 35 x86_64 emulator exercised UI quick-note creation, Mark Done and Reopen with native SharedPreferences. Recurrence and local backup export/replace-import were exercised through the controller on that emulator. Reminder delivery and platform backup pickers/sharing were not tested by this smoke. The private test harness is retained with the operator's evidence; it is not shipped in this source snapshot. A second native test after force-stop passed in a separate app process, restoring both items, their state, recurrence counter, attachment association and notification setting. These two distinct native workflows passed; the lifecycle smoke was also repeated with `--no-uninstall` to retain data for the restart check.

Preserved `integration_test/store_seed_test.dart` and `store_restart_test.dart` are available for native migration validation, but those specific tests were not executed in this preparation. They require an explicitly targeted disposable emulator and `--dart-define=STILLOPEN_DISPOSABLE_DEVICE=true`. The seed requires an initially empty app store and base64 synthetic legacy fixture; use `--no-uninstall` and a force-stop before the separate restart target to retain native data. Never target a physical phone or clear user data.

`flutter run --debug -d <emulator-serial>` is the manual developer launch command; use synthetic examples only. Core tests and controller smoke do not prove platform sharing, camera/provider behavior, locked-phone notifications, OEM behavior or runtime network privacy. Native iOS hosts are omitted and iOS is unverified.
