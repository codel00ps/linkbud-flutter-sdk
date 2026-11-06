# LinkBud Flutter SDK · 0.4.0 preview

A thin Android/iOS plugin around the existing [Kotlin](../linkbud-android-sdk/README.md) and [Swift](../linkbud-ios-sdk/README.md) previews. Native code owns URL/payload validation, Play referral exchange, manual iOS recovery, installation identity, backup-excluded pending storage, retry deadlines and acknowledgment history. Dart does not implement a second referral protocol or store journey state.

This is a 0.4.0 preview intended for integration testing. Signed-device, store-install and real host-authentication acceptance for the native SDKs and Flutter host remain open. It never promises automatic iOS recovery. Android and iOS setup, recovery behavior and acceptance evidence stay separate.

## Compatibility

| Component | Baseline |
| --- | --- |
| Flutter / Dart | Flutter 3.47.9 / Dart 3.13.7 verification toolchain; package requires Flutter >=3.47 and Dart >=3.13 <4 |
| Android | API 26+, compile/target SDK 36, JDK 17, Gradle 9.1.0, AGP 9.0.1, built-in Kotlin with KGP 2.3.20, Play Install Referrer 2.2; sample uses NDK 29.0.14206865 |
| iOS | iOS 15+, Swift 5.9 language mode, Xcode 15+; actual checked Xcode version is recorded in the roadmap |
| Native SDK sources | LinkBud Android 0.4.0 and iOS 0.4.0, tracked snapshots from the sibling native repositories |
| Runtime ownership | One engine, one main-isolate client, one fixed configuration per app process |

Other Flutter/Xcode versions are unverified. No web, desktop, background isolate or multi-engine API is offered. A second engine receives `engine_in_use`; changing configuration receives `configuration_locked`. Use separate application IDs/build flavors for environments. Restart the app process to switch configuration.

## Prepare and install locally

From the LinkBud root:

```sh
python3 flutter-sdk/tool/prepare_native.py --verify
cd linkbud-flutter-sdk
flutter pub get
flutter test
flutter analyze
```

The preparation command copies the exact native source files into tracked snapshot directories inside the plugin and writes their SHA-256 manifest. The bridge compiles these files directly; never edit the staged copies. Run it again after changing either native SDK. `--check` fails for missing, extra or altered source files. Run `--check` when both sibling native repositories are available to verify upstream parity. Run `--verify` in an independent Flutter checkout to verify bundled hashes without those repositories. A prepared package is self-contained and does not depend on an unpublished Maven or Swift registry.

Add a local `path:` dependency on this directory (as the sample does). For iOS, the package supplies both a CocoaPods specification and a Swift Package Manager manifest; CocoaPods is the checked integration in the pinned Flutter toolchain. The committed native snapshots are ready to build without the sibling repositories. Refresh them with `tool/prepare_native.py` only after native changes; `--android-sdk` and `--ios-sdk` accept alternate checkout paths. Set the host minimum Android SDK to 26, iOS deployment target to 15.0, and the Android toolchain to the versions above. CocoaPods must be installed to build the iOS sample with the documented setup.

## Host lifecycle and authentication

Listen before initializing. Keep the subscription for the app lifetime. Initialization returns the cold link or persisted restart result. Warm OS links arrive through `incoming`; this broadcast stream is not durable, so call `pending()`/`resume()` after missed events or restarting Dart. Native state remains authoritative. Disable Flutter's built-in deep-link router (`flutter_deeplinking_enabled=false` on Android and `FlutterDeepLinkingEnabled=false` on iOS) to avoid competing routing.

```dart
final linkbud = LinkBud.instance;
final subscription = linkbud.incoming.listen(onLinkBudResult, onError: onBridgeError);
final initial = await linkbud.initialize(const LinkBudConfiguration(
  origin: 'https://links.your-domain.com',
  applicationId: yourApplicationId,
  environment: 'testing',
  sdkId: yourEnvironmentSdkId,
  routePrefix: yourEnvironmentRoutePrefix, // Three characters, without slashes.
  appleAppId: yourAppleTeamAndBundleId, // Required on iOS; ignored on Android.
));
onLinkBudResult(initial);
```

Only use your environment's public identifiers; never ship a management credential. The native plugin receives Android VIEW intents and iOS browsing-web user activities. `handleUrl(url)` is available for host-managed entry points, but do not forward the same OS callback through two integrations. The native SDK validates the full origin/application/environment/prefix/code before any API request.

On `PendingDestination`, wait for actual host authentication. After login, call `resume()` and use its newly validated result. Allowlist and authorize the route before navigating, then `acknowledge(id)` **after** navigation succeeds. Neither a URL, token, recovery code nor pending route authorizes protected content. The sample allows only `/welcome` and labels its login as simulated. Real hosts must make navigation idempotent across a crash between navigation and acknowledgment; bounded native deduplication does not guarantee exactly-once navigation.

Serialize host operations. iOS returns `operation_in_progress` for an overlapping call; retry the original input after completion. An overlapping warm link produces `operation_in_progress_reopen_link`, so give the user a reopen action. A second distinct journey is rejected rather than replacing the current one. Cached `pending()` is for inspection, not delayed authorization. Native expiry applies even without cleanup jobs. Do not automatically acknowledge a rejected/unauthorized destination or clear state when presenting a login screen.

## Results and errors

| API/outcome | Meaning and host response |
| --- | --- |
| `initialize(config)` | Validates/locks configuration; returns cold-input or restart result |
| `incoming` | Warm native results; subscribe before initialization |
| `handleUrl(url)` | Explicit host-supplied URL; same native boundaries as OS input |
| `pending()` | Cached non-expired hint, without a network recheck |
| `resume()` | Revalidates pending input; on Android checks Play referrer when needed |
| `recover(code)` | Explicit user-entered iOS code; Android returns `unsupported_recovery` |
| `acknowledge(id)` | Persists native deduplication after navigation; false means it did not persist |
| `LinkBudEmpty` | No journey; offer original-link reopening/manual iOS recovery |
| `LinkBudAlreadyAcknowledged` | Do not navigate again |
| `LinkBudRetryable(retryAt)` | Preserve the hint and retry no earlier than this time on user/connectivity/lifecycle action |
| `LinkBudRejected(reason)` | No navigation; explain expiry/unavailability/conflict and offer reopening/new code as appropriate |
| `PlatformException` | Initialization, engine/configuration or operation failure; do not fabricate a destination |
| `FormatException` / malformed native response | Bridge contract failure; fail closed and retain diagnostic context without sensitive payloads |

There is no background polling. Android non-Play/unsupported referrer recovery requires reopening the original link. On iOS, a user requests a code on `/continue/...` and explicitly enters/pastes it in the app. The SDK never reads the clipboard. Do not log URLs with destination parameters, recovery codes, tokens, installation IDs or management credentials.

## Sample and validation

The sample includes complete Android/iOS host projects. Configure public values using Dart defines and the matching native association configuration described in [the Flutter device protocol](../linkbud/docs/flutter-device-validation.md). Do not expect the illustrative default identifiers/domain to resolve real links.

```sh
cd linkbud-flutter-sdk/example
flutter pub get
flutter run --dart-define=LINKBUD_ORIGIN=https://links.your-domain.com \
  --dart-define=LINKBUD_APPLICATION=YOUR_APPLICATION_ID \
  --dart-define=LINKBUD_SDK_ID=YOUR_SDK_ID \
  --dart-define=LINKBUD_APPLE_APP_ID=YOUR_TEAM.YOUR_BUNDLE
flutter test integration_test/bridge_test.dart -d YOUR_DEVICE_ID
```

The integration smoke test exercises the actual native channel with invalid links/codes, environment-locking and unknown acknowledgment. It does not prove OS association, successful network recovery, restart navigation or store installation. Dart tests exercise result mapping, cold/warm dispatch, forwarding and bridge errors; native SDK suites exercise persisted restart/auth waiting, replay, failure/backoff, expiry and deduplication. Execute the device protocol for end-to-end evidence.

## Packaging and release ownership

Version 0.4.0 is a public preview package intended for initial integration testing. The package archive includes the bridge, native source snapshots, sample and license; the repository is currently private, so its GitHub URL and sibling-repository links require access. Review the exact package contents with `dart pub publish --dry-run` before publishing. Publishing to pub.dev makes this version publicly downloadable; later fixes require a new package version.

To make a local distribution from the repository root:

```sh
python3 flutter-sdk/tool/prepare_native.py
python3 flutter-sdk/tool/prepare_native.py --check
python3 flutter-sdk/tool/package_preview.py /tmp/linkbud-flutter-0.4.0.tar.gz
```

The archive includes native sources and their manifest, the bridge, sample and license. It excludes caches, local settings and build outputs. Unpack it into a fresh directory, run `flutter pub get`, `flutter test` and build both sample hosts before distribution. The 0.4.0 preview is intended for package integration testing; signed device acceptance remains pending and is part of the follow-up validation.

## Basic analytics

The current native SDK persists a random per-journey event ID and sends it on direct link resolution, including OS-native opens that bypass web redirects. Restart, network retry and login revalidation reuse the ID. Successful deferred exchanges are counted once by the server. No installation identifier is sent for direct-open analytics. An SDK open means successful resolution, potentially before login; acknowledgment/navigation remains local. Upgrade the backend with the analytics migration before using these counts. Older servers ignore the additive request fields, and old SDKs continue resolving without direct-open counts. Read [the analytics contract](../linkbud/docs/analytics.md) for privacy, 30-day retention, public-client trust limits and queue operations.


## General link analytics (v2 preview)

The SDK requests v2 analytics on direct/recovered resolution. The server returns an optional,
short-lived opaque reporting receipt. Call the existing `acknowledge` only after actual authorized
navigation: it now atomically queues a destination-open report alongside the normal local progress.
Reports include only the receipt, outcome and elapsed SDK journey time, never the destination,
credentials, user IDs or installation identifier. Old servers without receipts still work.

For an abandoned destination, `destinationFailed(id, reason)` accepts only `navigation`,
`authentication`, `permission`, `unavailable`, or `unsupported`, persists the failure report and
finishes that local journey. Do not call this for a sign-in screen that is still waiting for login.
Flutter exposes the same method. This is not a business conversion or authorization API.

Delivery is best effort. Up to 16 reports persist outside backups; the oldest is evicted at the
bound. Reports retry on lifecycle resume/acknowledgement, honor bounded retry delays and expire with
the server receipt. Network errors do not undo successful navigation. No background polling occurs.
The dashboard separates browser clicks, successful resolution, completed navigation and store
redirects; none identify unique people or prove a download. Existing acknowledged-link deduplication
behavior and store/device acceptance limits remain unchanged. Rebuild host apps to use this version;
updating LinkBud alone cannot add destination reporting to an installed app.


## Testing and Live · 0.4.0 preview

Configure new integrations with testing or live. Staging is retired. Development and Production are accepted legacy aliases for Testing and Live respectively, including URL parsing. The backend echoes the requested API environment for older SDK payload validation. Association documents and Android manifest snippets include both canonical and legacy paths. Refresh app configuration/manifest when adopting new URLs; existing installed Android builds with only a development path filter cannot receive testing URLs until rebuilt. Keep legacy SDK configuration until outstanding pending journeys finish; changing the configured environment changes the SDK storage namespace.

## Short URLs · 0.4.0 preview

Configure `routePrefix` with the environment’s immutable three-character Base62 value, without
slashes. A short link is `https://LINK_HOST/Ab1/Cd34Ef`: prefix and code are case-sensitive.
Copy the real value from LinkBud Settings; the example is illustrative. The SDK sends the
configured application/environment/SDK IDs plus `route_prefix` and `code` to resolution and
checks the response against that context. Short links reject extra path segments, credentials,
custom ports, queries, fragments and encoded aliases.

The optional setting keeps existing constructors working. While the rollout flag is off, old
paths remain accepted for a staged upgrade; after activation the server rejects legacy slug
resolution and publishes only short paths in association documents. Update Android manifest
filters before activation; cached OS association changes may take time. Reopening an old URL
after cutover fails and requires a newly shared URL. Adding a prefix preserves stored installation
identity and pending recovery; always resume/revalidate before authorizing navigation. Recovery
responses include the same prefix/code context. Android still needs a matching Play installation;
iOS still requires explicit code entry or reopening the original short link after installation.
These source changes do not update Aurix or any installed build.
