# Mo Save — Android release

## Production identity

- Display name: `Mo Save`
- Android application ID / namespace: `com.samo.mosave`
- Initial production version: `1.0.0+1`

Versioning uses Flutter's `version: MAJOR.MINOR.PATCH+BUILD` value from `pubspec.yaml`. Increase the semantic version when product behavior changes and always increment the build number for every distributed Android artifact.

## Release permissions

The production manifest requests only:

- `POST_NOTIFICATIONS` for the optional local payday/goal reminders;
- `RECEIVE_BOOT_COMPLETED` so scheduled local reminders can be restored after a reboot.

`INTERNET` exists only in Flutter's debug/profile manifests for development tooling and is not requested by the production manifest.

Android automatic cloud backup is disabled because Mo Save owns its explicit portable `.mosave` backup/restore flow.

## Release signing

Never commit the keystore or real passwords. `android/.gitignore` excludes `key.properties`, `*.jks` and `*.keystore` files.

Create a private upload key locally from the project root on Windows:

```powershell
New-Item -ItemType Directory -Force android\keystore | Out-Null
keytool -genkeypair -v `
  -keystore android\keystore\mo-save-upload.jks `
  -alias upload `
  -keyalg RSA -keysize 2048 -validity 10000
```

Then copy `android/key.properties.example` to `android/key.properties` and replace both passwords with the values you chose. Keep the `storeFile` value as:

```text
../keystore/mo-save-upload.jks
```

Back up the keystore and its passwords privately. Losing the signing key can prevent future updates to installs signed with that key.

The Gradle release configuration intentionally does not fall back to the debug signing key. A production release command without local signing configuration fails instead of silently producing a debug-signed artifact.

## Build

From the project root:

```powershell
flutter pub get
flutter build apk --release
flutter build appbundle --release
```

Expected outputs:

```text
build\app\outputs\flutter-apk\app-release.apk
build\app\outputs\bundle\release\app-release.aab
```

For direct client installation use the signed APK. For a store upload use the signed AAB.

## Install verification

With the target Android device connected through ADB:

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Before closing Issue #28, verify on the target device that:

1. the launcher shows `Mo Save`;
2. Android reports package `com.samo.mosave`;
3. the app opens in release mode and existing core workflows load;
4. notification permission is requested only when a reminder is enabled;
5. local reminders can be scheduled;
6. backup export/restore remains usable;
7. the signed release can be reinstalled/upgraded using the same signing key.

## Branding asset status

The Android identity and display name are production-ready. The repository currently retains the existing launcher/splash artwork. Replace those assets only with owner/client-approved final artwork before calling the branding portion final.
