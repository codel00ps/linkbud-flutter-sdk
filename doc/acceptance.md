# Flutter host acceptance

Follow [the SDK guide](../README.md). The plugin wraps the native SDKs; verify Android and iOS independently. The sample's login is simulated. Use a host with real authentication/authorization for acceptance.

## Configure the sample

From `example`, build/run with `LINKBUD_ORIGIN`, `LINKBUD_APPLICATION`, `LINKBUD_SDK_ID`, `LINKBUD_ROUTE_PREFIX` and `LINKBUD_APPLE_APP_ID` Dart defines. Environment defaults to `default`. Android derives the host, short-path prefix and legacy path filter from the same defines. Use the actual three-character prefix and real short link from LinkBud Settings. Sign with the registered distribution certificate; set the Gradle `linkbudPackage` property for the registered package.

For iOS, set `LINKBUD_HOST` in ignored `example/ios/Flutter/Local.xcconfig` and configure Runner's bundle ID, signing team and Associated Domains in Xcode. Match that host and team/bundle in the Dart configuration and LinkBud association. The Dart `routePrefix` reaches both native SDKs; the iOS entitlement is host-based and path ownership comes from AASA and native validation.

Keep Flutter's built-in deep-link router disabled on both platforms. Subscribe to `incoming` before `initialize`; use the returned result for cold links and persisted restart input. One engine, main isolate and configuration are supported. A second engine or a different configuration must fail visibly. If the host forwards URLs itself, avoid forwarding the same OS callback twice. Unrelated URLs must reach their own handlers; before Dart configuration the plugin cannot claim URL ownership and retains only one tentative cold input.

## Platform acceptance

On Android, verify `assetlinks.json`, `autoVerify` manifest filters and signed cold/warm App Links on an older and current OS. On a physical Play device, uninstall, tap a real short link, install from the operator's Play testing track and recover via Install Referrer. Check lost-response restart, claiming-installation stability, different-installation rejection, canceled/delayed installation and unavailable/non-Play referrer behavior.

On iOS, verify AASA, Associated Domains and signed cold/warm Universal Links on supported older/current iOS and iPad. After fresh App Store/TestFlight installation, launcher opening must not invent a destination. Explicitly request and enter a code, retry a lost response, and test code expiry/replay/wrong identity. Confirm no silent clipboard access or automatic App Store recovery.

Check both documented Flutter toolchains. `flutter test integration_test/bridge_test.dart -d DEVICE_ID` exercises native channel validation and explicit reopening rejection; it does not prove real network recovery, OS routing or store installation. Build from an extracted package, and separately repeat installation from the actual public package version after publication.

## Shared failure and navigation checks

- Keep a pending journey through real login and process restart. Call `resume` after authentication, authorize the returned route, navigate idempotently and only then acknowledge. Restart again and confirm no repeated navigation.
- Disable, delete or expire the link while login is pending. Revalidation must prevent stale cached routing. Reject another host, wrong application/environment/prefix, credentials, ports, encoded path aliases, queries and fragments.
- Deliver duplicate OS callbacks and confirm the completed URL returns `alreadyAcknowledged`. After leaving the destination, deliberately call `reopen` and confirm a new delivery/event identity and fresh server validation. Reopening must not replace another pending journey or bypass link unavailability.
- Restart offline, reconnect and honor `retryAt`; test 429/5xx, lost responses, expiry and storage failure. Keep navigation responsive and prevent a second distinct link from overwriting the current journey.
- Test v2 destination reports after acknowledgment/failure, offline persistence and retry. Inspect aggregate counts without storing receipt/token values. See [analytics](analytics.md).

## Evidence

Record date, device/OS, toolchain, host app version/commit, public origin, app identity, install source, association diagnostics and cold/warm/restart/authentication/recovery outcomes. Use disposable data. Never record credentials, codes, tokens, installation IDs or destination queries. Unit tests and unsigned builds do not establish signed-device associations, store installation or real host authentication. Rerun this protocol for every host app and release candidate.
