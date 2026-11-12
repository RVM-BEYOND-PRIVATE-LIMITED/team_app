# rvm_team_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Release signing

A release build (`flutter build apk --release`, `flutter build appbundle`,
`flutter run --release`) is signed with the release key named in
`android/key.properties` (team_app #50, item 9). Debug and profile builds keep
the debug key and never read that file.

`android/key.properties` and every `*.jks` / `*.keystore` file are git-ignored
(`android/.gitignore`). Never commit them, never paste them into an issue or a
pull request, and never print them in a workflow log: this repository is public.
The release keystore and its sealed backup are held by the key's custodian, not
by the repository.

To sign a release build, create `android/key.properties`:

```properties
storeFile=/absolute/path/to/release.jks
storePassword=<the keystore password>
keyAlias=<the key's alias>
keyPassword=<the key's password>
```

`storeFile` is an absolute path, or a path relative to `android/app`. Keep the
keystore outside the repository.

Without that file, or with a value missing, or with a `storeFile` that does not
exist, a release build stops at once with a message that says which. It never
falls back to the debug key.

Release builds keep R8 code shrinking (`isMinifyEnabled`) and resource shrinking
(`isShrinkResources`) on; `android/app/build.gradle.kts` pins both. Resources
that only Dart code names (the urgent channel's sound, the large notification
icon) are kept by `android/app/src/main/res/raw/keep.xml`.

A release-signed build cannot be installed over a debug-signed one: uninstall
the debug build first.

To try a release build on your own machine without the real key, make a
throwaway key outside the repository and point `android/key.properties` at it:

```sh
keytool -genkeypair -keystore /tmp/throwaway.jks -storetype PKCS12 \
  -alias throwaway -keyalg RSA -keysize 2048 -validity 7 \
  -dname "CN=Throwaway local test key, O=Not for release"
```

Set `CI=true` for such a build, so its R8 mapping is not uploaded to the
production Firebase project.

## CI

`.github/workflows/flutter.yml` runs on every pull request that touches
`flutter_app/**` (whatever its base branch) and on pushes to `main`: Flutter
3.35.7 and JDK 17, `flutter analyze` and `flutter test` for this app and each
`packages/*`, then the split-per-ABI release APKs and the App Bundle, signed
with a key made for that run only. It prints each file's size and fails when the
largest APK or the App Bundle is 100 MB (104857600 bytes) or more, or when the
built APK asks for a call, call-log or phone-state permission.
