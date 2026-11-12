import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkbud_flutter_example/main.dart';

void main() {
  testWidgets(
    'sample waits for login, revalidates, then acknowledges allowed navigation',
    (tester) async {
      final calls = <String>[];
      final pending = {
        'status': 'pending',
        'id': 'demo',
        'destination': '/welcome',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.linkbud/flutter'),
            (call) async {
              calls.add(call.method);
              if (call.method == 'initialize') {
                expect(
                  (call.arguments as Map)['routePrefix'],
                  const String.fromEnvironment(
                    'LINKBUD_ROUTE_PREFIX',
                    defaultValue: 'Ab1',
                  ),
                );
              }
              return switch (call.method) {
                'initialize' => null,
                'acknowledge' => true,
                _ => pending,
              };
            },
          );
      await tester.pumpWidget(const MaterialApp(home: LinkBudExample()));
      await tester.pumpAndSettle();
      expect(
        find.text('Destination waiting for simulated login.'),
        findsOneWidget,
      );
      expect(calls, ['initialize', 'start']);
      await tester.tap(find.text('Simulate login and revalidate'));
      await tester.pumpAndSettle();
      expect(calls, ['initialize', 'start', 'resume', 'acknowledge']);
      expect(
        find.text('Welcome! Simulated authorized navigation.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('sample refuses a host route outside its allowlist', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.linkbud/flutter'), (
          call,
        ) async {
          calls.add(call.method);
          return call.method == 'initialize'
              ? null
              : {
                  'status': 'pending',
                  'id': 'unsafe',
                  'destination': '/admin',
                  'expiresAt': DateTime.now()
                      .toUtc()
                      .add(const Duration(hours: 1))
                      .toIso8601String(),
                };
        });
    await tester.pumpWidget(const MaterialApp(home: LinkBudExample()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simulate login and revalidate'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Expired or unsupported route. Only /welcome is allowed in this sample.',
      ),
      findsOneWidget,
    );
    expect(calls, isNot(contains('acknowledge')));
    await tester.pumpWidget(const SizedBox());
  });
}
