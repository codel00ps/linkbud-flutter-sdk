# Flutter 1.0.1 release candidate

The package, Android project, CocoaPods specification and example version target 1.0.1. The native-source manifest tracks the matching Android/iOS sources. Flutter 3.32 / Dart 3.8 and native API 23 / iOS 15 support are retained; the host Flutter engine can impose a higher Android minimum.

```sh
python3 tool/prepare_native.py --check
python3 -m unittest discover -s tool/tests
flutter analyze
flutter test
flutter pub publish --dry-run
```

Use `--verify` instead of `--check` in an independent package checkout. Extract the candidate archive and check both documented Flutter toolchains, example tests, Android APK and iOS simulator builds. The sample's `LINKBUD_ROUTE_PREFIX` must reach the native configuration and Android manifest. The AGP 9 sample profile uses Flutter 3.47+, Gradle 9.1.0, AGP 9.0.1 and Kotlin 2.2.21 declared early with `apply false`. Keep `android.builtInKotlin=true` and `android.newDsl=false`; do not skip Flutter's dependency checks. See [the compatibility guide](../README.md#agp-8-and-agp-9-hosts).

Debug simulator builds use the Mac's native architecture to avoid the older Flutter/Xcode 27 multi-architecture `lipo` issue. Device/release architectures and deployment targets are unchanged. Older Flutter may print benign debug-plist probe/deprecation messages even after a successful build.

Review the exact package file list, native hashes, license, source/docs and absence of local secrets. Commit the reviewed source and create the new 1.0.1 release tag. Run `flutter pub publish` only at the final publication step. Publication is not performed by the packaging tool or dry run. After publication, install 1.0.1 from pub.dev in a clean host, separately from the local candidate checks. Follow [device acceptance](acceptance.md) for actual App/Universal Links, Play installation, recovery and authentication.

## Host migration

Configure `environment` as `default`, matching the backend's single application configuration. Testing/Live and Development/Production names are retired; changing the configured environment changes the storage namespace. Coordinate this with the existing backend rollout and finish/revalidate outstanding journeys before changing host configuration. Use the real immutable short-link prefix and rebuild/distribute the host app.

Android and iOS now both reject legacy URL queries/fragments. Share canonical URLs. Reopening is explicit, server-validated and intended for a deliberate repeat user activation; duplicate OS callbacks keep normal acknowledgment protection. No database migration is introduced by this SDK patch.
