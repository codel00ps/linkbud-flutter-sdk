# 0.4.0 preview

- Add optional public `routePrefix` configuration and strict six-character short-path resolution.
- Bind direct/recovery responses to the configured prefix; preserve persisted installation identity.
- Migrate the Android plugin and example to AGP built-in Kotlin; require Flutter 3.47 and Dart 3.13 or newer.
- Retain legacy parsing during rollout; server-side activation rejects old slug resolution.
- Update samples and Flutter native snapshots. Store/device release acceptance remains separate.

# 0.3.0 preview · unpublished

- Support Testing/Live and matching Development/Production URL aliases.
- Reject retired Staging configuration; preserve strict application/environment isolation.

# 0.3.0 preview · unpublished

- General analytics v2: persistent destination outcomes, bounded offline retry, and fixed failure reasons.
- Existing resolution and authentication contracts remain supported.

# Unreleased · 2026-10-27

- Stage native per-journey analytics ID support; Dart API and navigation acknowledgment remain unchanged.

# 0.1.0 — local preview

- Add an Android/iOS Flutter method-channel bridge over the unchanged LinkBud 0.1.0 native sources.
- Expose cold/warm link results, manual URL input, pending lookup, revalidation, iOS manual recovery and acknowledgment.
- Add a sample, bridge tests, native-source parity checks and local packaging instructions.
- Signed association, real store installation and real host-authentication acceptance remain deferred; no registry publication or automatic iOS recovery is claimed.
