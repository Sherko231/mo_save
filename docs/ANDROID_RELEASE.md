# Mo Save — Android direct build

## App identity

- Display name: `Mo Save`
- Android application ID / namespace: `com.samo.mosave`
- Current version comes from `pubspec.yaml`.

The previous development application ID was `com.example.mo_save`. Android treats `com.samo.mosave` as a different application, so an old development install will not upgrade in place. If that old install contains data worth keeping, export a `.mosave` backup before removing it, then restore that backup inside the current app.

## Permissions

The release manifest requests only:

- `POST_NOTIFICATIONS` for optional local payday/goal reminders;
- `RECEIVE_BOOT_COMPLETED` so scheduled local reminders can be restored after a reboot.

`INTERNET` exists only in Flutter's debug/profile manifests for development tooling and is not requested by the release manifest.

Android automatic cloud backup is disabled because Mo Save owns its explicit portable `.mosave` backup/restore flow.

## Build an APK

No private release setup is required.

From the project root:

```powershell
flutter pub get
flutter build apk --release
```

The APK is created at:

```text
build\app\outputs\flutter-apk\app-release.apk
```

The project uses Android's automatically managed debug signing for the release build so the APK can be installed directly without any manual secrets or configuration. This setup is intended for direct/private distribution rather than an app store.

## Install on a connected device

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Or copy `app-release.apk` to the phone and open it there.

## Data migration note

If a device still has the old `com.example.mo_save` development build, export a `.mosave` backup from it before uninstalling. Install the current `com.samo.mosave` build, then restore the backup.

## Branding asset status

The Android identity and display name are configured. Launcher/splash artwork can be replaced later without changing the financial data model.
