# 1.0.1 — November 12, 2026

- Align SDK/sample release metadata to 1.0.1 and configuration to the backend's single `default` environment. Retired environment names must be migrated before rebuilding.

- Make the sample select AGP 8 or 9, retain an early Kotlin version declaration and apply KGP only when built-in Kotlin is absent. Keep Flutter's legacy DSL compatibility enabled for AGP 9.
- Build debug iOS simulators for the Mac's native architecture (normalizing arm64e to arm64), avoiding older Flutter's multi-architecture `lipo` failure with Xcode 27 while preserving device architectures.
- Align SDK, CocoaPods and sample versions to 1.0.1; retain Flutter 3.32 / Dart 3.8, API 23 and iOS 15 support.
- Configure short-link sample routing through `LINKBUD_ROUTE_PREFIX` on both native platforms and retain Android legacy filters.
- Expose explicit `reopen` on both bridges; preserve duplicate-callback and pending-journey protection.
- Check configured URL ownership before claiming OS events and ignore unrelated cold input at startup.
- Document the public Dart API, fix analyzer style and sample labels, consolidate the historical changelog, and bundle integration/analytics guides.
- Refresh bundled native sources and their hash manifest.

# 1.0.0 — November 11, 2026

- Establish the stable 1.x Dart API baseline without changing the 0.4.1 bridge/runtime contract.
- Align pubspec, Android, CocoaPods and example versions to 1.0.0.
- Verify bundled sources against the native Android/iOS 1.0.0 sources; keep the distribution self-contained.
- Document supported toolchains, required Android desugaring, explicit iOS recovery, privacy and host-owned authentication/navigation responsibilities.
- Record owner-confirmed real-device acceptance, keeping the sample's simulated login clearly distinguished.
- Make the Android example respect the Flutter engine minimum and remove stale generated Swift-package references from the iOS example.

Earlier entries describe historical preview milestones, not the current release status.

# 0.4.1 preview

- Match the native SDK minimums: Android API 23+ and iOS 15+. Set the plugin and sample Android minimum explicitly to 23; all Android hosts must enable core library desugaring, including apps with a minimum API of 26 or higher.
- Support Flutter 3.32 / Dart 3.8 and the AGP 8 Kotlin Gradle Plugin alongside AGP 9 built-in Kotlin hosts. Use Flutter 3.32.8 for API 23 deployment; newer Flutter engines may require a higher Android API independently of this plugin.
- Use the Flutter 3.32-compatible application-delegate lifecycle in the iOS sample, retaining the iOS 15.0 deployment target.
- Bundle the Android storage hardening: reject further state operations after a write failure until the app restarts, preventing use of unpersisted navigation state or installation identity.

# 0.4.0 preview

- Add optional public `routePrefix` configuration and strict six-character short-path resolution.
- Bind direct/recovery responses to the configured prefix; preserve persisted installation identity.
- Migrate the Android plugin and example to AGP built-in Kotlin; require Flutter 3.47 and Dart 3.13 or newer.
- Retain legacy parsing during rollout; server-side activation rejects old slug resolution.
- Update samples and Flutter native snapshots. Store/device release acceptance remains separate.

# 0.3.0 preview · unpublished

- Support Testing/Live and matching Development/Production URL aliases.
- Reject retired Staging configuration; preserve strict application/environment isolation.

- General analytics v2: persistent destination outcomes, bounded offline retry, and fixed failure reasons.
- Existing resolution and authentication contracts remain supported.

# Unreleased · 2026-10-27

- Stage native per-journey analytics ID support; Dart API and navigation acknowledgment remain unchanged.

# 0.1.0 — local preview

- Add an Android/iOS Flutter method-channel bridge over the unchanged LinkBud 0.1.0 native sources.
- Expose cold/warm link results, manual URL input, pending lookup, revalidation, iOS manual recovery and acknowledgment.
- Add a sample, bridge tests, native-source parity checks and local packaging instructions.
- Signed association, real store installation and real host-authentication acceptance remain deferred; no registry publication or automatic iOS recovery is claimed.
