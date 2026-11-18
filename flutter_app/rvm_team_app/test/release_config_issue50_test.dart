import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// team_app #50, items 9 and 11: the release build is signed from a git-ignored
/// android/key.properties (never the debug key), keeps code and resource
/// shrinking on, and CI builds it and holds it under 100 MB. The builds prove
/// the behaviour (the Flutter workflow on every pull request); this test keeps
/// the settings from being dropped by an edit.
void main() {
  final gradle = File('android/app/build.gradle.kts');
  final workflow = File('../../.github/workflows/flutter.yml');

  /// The `release { ... }` block inside `buildTypes`.
  String releaseBuildType(String source) {
    final buildTypes = source.indexOf('buildTypes {');
    expect(buildTypes, isNonNegative, reason: 'no buildTypes block');
    final start = source.indexOf('release {', buildTypes);
    expect(start, isNonNegative, reason: 'no release build type');
    var depth = 0;
    for (var i = source.indexOf('{', start); i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}' && --depth == 0) return source.substring(start, i);
    }
    fail('release build type is not closed');
  }

  group('release signing (item 9)', () {
    test('release is signed with the release config, never the debug key', () {
      final release = releaseBuildType(gradle.readAsStringSync());
      expect(release, contains('signingConfigs.getByName("release")'));
      expect(release, isNot(contains('getByName("debug")')));
    });

    test('code and resource shrinking stay on for release', () {
      final release = releaseBuildType(gradle.readAsStringSync());
      expect(release, contains('isMinifyEnabled = true'));
      expect(release, contains('isShrinkResources = true'));
    });

    test('the key comes from android/key.properties, checked before a release',
        () {
      final source = gradle.readAsStringSync();
      expect(source, contains('rootProject.file("key.properties")'));
      for (final key in [
        'storeFile',
        'storePassword',
        'keyAlias',
        'keyPassword'
      ]) {
        expect(source, contains('"$key"'), reason: key);
      }
      // The check runs ahead of every release task and stops with a message.
      expect(source, contains('preReleaseBuild'));
      expect(source, contains('throw GradleException('));
    });

    test('git ignores key.properties and keystore files', () {
      final ignored = File('android/.gitignore').readAsLinesSync();
      expect(ignored, containsAll(['key.properties', '**/*.keystore', '**/*.jks']));
    });
  });

  group('the Flutter workflow (item 11)', () {
    test('runs on pull requests that touch flutter_app/, into any branch', () {
      final yml = workflow.readAsStringSync();
      expect(yml, contains("- 'flutter_app/**'"));
      expect(yml, contains("- '.github/workflows/flutter.yml'"));
      final pullRequest = yml.substring(
          yml.indexOf('pull_request:'), yml.indexOf('push:'));
      expect(pullRequest, isNot(contains('branches')));
    });

    test('builds with Flutter 3.35.7 and JDK 17 and fails at 100 MB', () {
      final yml = workflow.readAsStringSync();
      expect(yml, contains("FLUTTER_VERSION: '3.35.7'"));
      expect(yml, contains("java-version: '17'"));
      expect(yml, contains('SIZE_LIMIT_BYTES: 104857600'));
      expect(yml, contains('flutter build apk --release --split-per-abi'));
      expect(yml, contains('flutter build appbundle --release'));
      expect(yml, contains('-ge "\$SIZE_LIMIT_BYTES"'));
      // The workflow makes its own key; it reads no signing secret.
      expect(yml, isNot(contains('secrets.')));
    });
  });
}
