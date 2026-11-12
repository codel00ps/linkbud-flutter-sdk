import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linkbud_flutter/linkbud_flutter.dart';
import 'package:linkbud_flutter_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real native channel validates configuration and rejects unsafe input',
    (tester) async {
      final sdk = LinkBud.instance;
      const config = LinkBudConfiguration(
        origin: 'https://links.example.com',
        applicationId: 'aaaaaaaaaaaaaaaaaaaaaaaaaa',
        environment: 'default',
        sdkId: 'bbbbbbbbbbbbbbbbbbbbbbbbbb',
        routePrefix: String.fromEnvironment(
          'LINKBUD_ROUTE_PREFIX',
          defaultValue: 'Ab1',
        ),
        appleAppId: 'A1B2C3D4E5.dev.linkbud.sample',
      );
      // Android may return retryable/unavailable for Play services on an emulator.
      expect(await sdk.initialize(config), isA<LinkBudResult>());
      expect(await sdk.pending(), isA<LinkBudEmpty>());
      for (final url in [
        'http://links.example.com/l/unsafe',
        'https://other.example.com/l/unsafe',
        'https://links.example.com/l/aaaaaaaaaaaaaaaaaaaaaaaaaa/staging/ABCDEFGHIJKLMNOP',
      ]) {
        expect(
          (await sdk.handleUrl(url) as LinkBudRejected).reason,
          'invalid_link',
        );
        expect(
          (await sdk.reopen(url) as LinkBudRejected).reason,
          'invalid_link',
        );
      }
      expect(await sdk.acknowledge('unknown'), false);
      final recovery = await sdk.recover('invalid') as LinkBudRejected;
      expect(
        recovery.reason,
        Platform.isIOS ? 'invalid_recovery_code' : 'unsupported_recovery',
      );
      await expectLater(
        sdk.initialize(
          const LinkBudConfiguration(
            origin: 'https://links.example.com',
            applicationId: 'aaaaaaaaaaaaaaaaaaaaaaaaaa',
            environment: 'staging',
            sdkId: 'cccccccccccccccccccccccccc',
            appleAppId: 'A1B2C3D4E5.dev.linkbud.staging',
          ),
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(await sdk.pending(), isA<LinkBudEmpty>());
      app.main();
      await tester.pumpAndSettle();
      expect(find.text('LinkBud Flutter sample'), findsOneWidget);
      expect(find.textContaining('Operation failed.'), findsNothing);
      expect(
        find.text(
          'Demo login only. Real authentication and route authorization belong to the host app.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Use entered code'),
        Platform.isIOS ? findsOneWidget : findsNothing,
      );
    },
  );
}
