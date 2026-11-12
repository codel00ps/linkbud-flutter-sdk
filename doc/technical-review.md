# SDK technical review follow-up — November 12, 2026

This review checks the attached assessment against the current three SDK checkouts. Existing changes consolidating application configuration into environment `default` are preserved. New behavior is additive except for explicitly rejecting legacy URL queries/fragments, which now matches iOS. These changes are prepared as the 1.0.1 release candidate; published 1.0.0 artifacts and tags have not been replaced.

## Claims and decisions

| Claim | Investigation and implementation |
| --- | --- |
| A — Flutter sample omits short links | Confirmed. `LINKBUD_ROUTE_PREFIX` now reaches Dart configuration and both native bridges. Android generates a separate short-path filter while preserving the legacy filter. The sample guide includes the define. The integration smoke configuration matches the sample prefix. An APK built with `Xy9` was inspected: it contains `/Xy9/` and `/l/{application}/default/`. A real public link/device association remains a host acceptance check. |
| B — repeated-link inconsistency | Confirmed as a missing explicit API in Android/Flutter. iOS already had the intended operation. Android now implements `reopen(url, callback)` and Dart exposes `reopen(url)` through both bridges. Completed URLs get fresh delivery/event identities and server validation. Ordinary callbacks retain deduplication. A current journey cannot be replaced; callers resume it after authentication or retry. Tests cover fresh identity, persistence, backoff, callback suppression, conflicts and server unavailability. No automatic reopening was introduced. |
| C — native handlers claim unrelated URLs | Confirmed. Side-effect-free configuration ownership checks reuse each platform's complete native URL parser. Configured Flutter handlers return false for other hosts, OAuth paths, unsupported prefixes and malformed links, without mutating the Android activity intent or resolving them. Before Dart configuration, a single tentative cold input is retained without claiming ownership; startup filters it before processing. |
| D — inaccessible repositories/docs | The Android repository and the referenced backend documentation returned public 404s. Flutter/iOS repositories are public. Each SDK now bundles its own acceptance and analytics guides and README links resolve within its repository/package. The generated Maven project URL is the product homepage, `https://linkbud.io`; SCM still truthfully names the actual Android repository. Public homepage reachability could not be verified by the web tool. Pushing/publishing the guides, repairing repository visibility or providing a public source mirror, and updating future published metadata are release/operator work. No repository visibility or remote metadata was changed. |
| E — legacy parser discrepancy | Confirmed, including an Android test that deliberately accepted query/fragment suffixes. Android now rejects them. Android/iOS consume identical JSON vectors for valid short/legacy URLs and invalid hosts, contexts, suffixes, ports, credentials and encoded aliases. The distribution suite checks vector parity when both native checkouts are available. |
| F — analyzer/docs/polish | The [published pub.dev report](https://pub.dev/packages/linkbud_flutter/score) reports 150/160 and 9/37 documented API elements, and identifies the unbraced null-result guard. The guard and other library single-line guards now use braces; public Dart declarations have documentation comments. The current analyzer is clean. The Android sample label and integration expectation now say “sample”; duplicate historical 0.3.0 headings are consolidated. The plural package documentation folder was renamed to `doc` after a publication dry run flagged Pub's layout convention. |

## Architecture checks

The assessment's architectural observations match the source: Flutter delegates protocol/state to bundled native implementations; Android uses Play Install Referrer; iOS requires explicit code entry or a subsequent URL activation. Both native transports disable redirects, bound successful response bodies and use timeouts. State is app-private and backup-excluded, pending journeys retain retry/expiry information, and acknowledgment is separate from host authentication/authorization. Navigation outcomes use bounded opaque receipts and fixed failure categories. Native snapshots and SHA-256 hashes have been refreshed and checked against their sibling SDKs.

This is a focused source review and regression check, not independent signed-device/store acceptance or a comprehensive security audit. The earlier owner-reported November 11 device results have not been represented as newly reproduced evidence.

## Changed files

- Android: `Protocol.kt`, `ResolutionEngine.kt`, `LinkBud.kt`, `sdk/build.gradle.kts`, `ResolutionEngineTest.kt`, URL test fixtures, README/changelog and bundled guides.
- iOS: `Protocol.swift`, test resources in `Package.swift`, `LinkBudTests.swift`, matching URL fixtures, README/changelog and bundled guides. Existing reopening logic is retained.
- Flutter: public Dart API, Kotlin/Swift plugin bridges, mirrored native files and hash manifest; sample Dart configuration, Android Gradle/manifest, integration/widget tests and sample guide; method-channel/distribution tests, README/changelog and bundled guides.

## Verification for 1.0.1

- Android: 38 JVM tests, SDK release lint and sample debug lint pass; release AAR and sample APK build. Maven POM/Gradle metadata use 1.0.1. The unsigned source JAR matches the checkout. A clean consumer resolves the staged 1.0.1 AAR and compiles the new ownership/reopening APIs.
- iOS: 33 Swift tests pass in the checkout and again from an extracted source archive. The native sample's unsigned iOS device-target Release build passes.
- Flutter 3.47.9 / Dart 3.13.7: analyzer clean; 15 channel tests and two sample widget tests pass; extracted-package Android APK and ordinary iOS simulator builds pass. This engine makes the sample minSdk 24 while the plugin remains at API 23.
- Flutter 3.32.8 / Dart 3.8.1: analyzer clean; 15 channel tests and two sample widget tests pass; Android arm64 APK builds with minSdk 23. The ordinary iOS simulator build passes with the Debug simulator architecture mapping, without overriding architecture on the command line.
- AGP 9.0.1 / Gradle 9.1.0 / Flutter 3.47.9 builds the sample with built-in Kotlin enabled and dependency validation active. Kotlin 2.2.21 remains declared early with `apply false`; the app only applies KGP when no Kotlin extension exists. `android.newDsl=false` retains the Flutter-required legacy DSL compatibility. AGP 8 remains the older Flutter default.
- Xcode 27 simulator Debug builds select one native slice and map arm64e host processes to arm64. Older Flutter no longer calls lipo for multiple slices; newer Flutter does not request a nonexistent arm64e simulator slice. Device/release architectures are unchanged. See [the compatibility guide](../README.md#older-flutter-with-xcode-27).
- Four Python distribution tests and native source/hash parity checks pass. Documentation file links and all SDK/sample versions are verified.

The final package dry run and archive checks are recorded in [the release guide](release-1.0.1.md). Tests use local candidates, not newly published public versions. No signed-device/store acceptance or OS-event runtime smoke test was performed for this patch.

## Release and host follow-up

No database migration or server deployment is required by this patch. Version metadata and release candidates are prepared for 1.0.1; sign, tag and publish through the existing release process. The new APIs are unavailable in published 1.0.0. Rebuild and distribute host applications to deliver changes. Existing server-side environment/short-link rollout requirements remain applicable.

Legacy URLs with tracking queries or fragments are intentionally rejected now. Configure the real short prefix in the host manifest and SDK, and migrate callers to canonical links. Hosts must authenticate and authorize each fresh result and keep navigation idempotent.

Use the bundled acceptance guide for signed cold/warm App/Universal Links, fresh Play installation/referrer, explicit iOS recovery, real authentication/restart, repeated/concurrent links, offline retry, expiry and analytics outcomes. Repeat clean consumer installation from actual public distribution channels after publication. These physical-device/store checks were not performed in this task. Publishing documentation and resolving Android source-repository visibility remain external release work.
