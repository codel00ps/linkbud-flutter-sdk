# Flutter SDK 2.0.0 release candidate

The `linkbud_flutter` source archive includes its Kotlin and Swift snapshots, their hash manifest,
the example and contract tests. It builds independently of the standalone SDK repositories.

## Local verification

In the SDK checkout run `python3 tool/prepare_native.py --check`, then create the candidate with
`python3 tool/package_preview.py /absolute/path/to/linkbud-flutter-sdk-2.0.0.tar.gz`. Extract it
outside the SDK checkouts. Run `python3 tool/prepare_native.py --verify`,
`python3 -m unittest discover -s tool/tests`, `flutter analyze` and `flutter test`.
Run the example widget tests and build its Android APK. From `example`, run
`FLUTTER_SWIFT_PACKAGE_MANAGER=false flutter build ios --simulator --no-codesign`
to check the supported CocoaPods integration.
Review the package contents with `flutter pub publish --dry-run`.

## Host and release acceptance

Use the managed HTTPS origin and public IDs from Settings → Domains. Supply only the exported
additional incoming-link hosts. Retain the managed hostname in both platform declarations and
rebuild after declaration changes. Check the six-character app-link path and confirm that
`/continue/{code}` stays in the browser. Remove retired route-prefix configuration from host apps.

Follow [signed-device acceptance](acceptance.md) on both platforms, including Play Install
Referrer and explicit iOS recovery. Verify an exact `linkbud_flutter: 2.0.0` dependency in a clean
host after publication.
