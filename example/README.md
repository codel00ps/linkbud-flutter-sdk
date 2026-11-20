# LinkBud Flutter sample

See [the SDK guide](../README.md) and [device acceptance](../doc/acceptance.md). Login is simulated. Configure your own public HTTPS origin and identifiers; the defaults are illustrative.

```sh
flutter run --dart-define=LINKBUD_ORIGIN=https://links.your-domain.com \
  --dart-define=LINKBUD_APPLICATION=YOUR_APPLICATION_ID \
  --dart-define=LINKBUD_SDK_ID=YOUR_SDK_ID \
  --dart-define=LINKBUD_APPLE_APP_ID=YOUR_TEAM.YOUR_BUNDLE
```

Copy the permanent application origin from Settings → Domains. Android matches a six-character code path on that host; iOS must use the same Associated Domains host and signing identity. Test a real generated URL on a signed device.
