# LinkBud Flutter sample

See [the SDK guide](../README.md) and [device acceptance](../doc/acceptance.md). Login is simulated. Configure your own public HTTPS origin and identifiers; the defaults are illustrative.

```sh
flutter run --dart-define=LINKBUD_ORIGIN=https://links.your-domain.com \
  --dart-define=LINKBUD_APPLICATION=YOUR_APPLICATION_ID \
  --dart-define=LINKBUD_SDK_ID=YOUR_SDK_ID \
  --dart-define=LINKBUD_ROUTE_PREFIX=Ab1 \
  --dart-define=LINKBUD_APPLE_APP_ID=YOUR_TEAM.YOUR_BUNDLE
```

Replace `Ab1` with the exact three-character prefix from LinkBud Settings. Dart passes it to both native SDKs. Android creates `/{prefix}/` and legacy `/l/{application}/default/` manifest filters from the same defines. For iOS, also set the Associated Domains host and signing identity as described in the guide. Test an actual current-format URL from LinkBud after installing a signed host; the placeholder domain cannot validate real routing.
