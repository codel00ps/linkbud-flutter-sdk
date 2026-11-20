import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkbud_flutter/linkbud_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.linkbud/flutter');
  const config = LinkBudConfiguration(
    origin: 'https://links.example.com',
    applicationId: 'aaaaaaaaaaaaaaaaaaaaaaaaaa',
    environment: 'default',
    sdkId: 'bbbbbbbbbbbbbbbbbbbbbbbbbb',
    appleAppId: 'A1B2C3D4E5.dev.linkbud.sample',
  );
  final calls = <MethodCall>[];
  Object? response = {'status': 'empty'};
  PlatformException? failure;

  setUp(() {
    calls.clear();
    response = {'status': 'empty'};
    failure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (failure != null) throw failure!;
          if (call.method == 'initialize') return null;
          return response;
        });
  });

  test('operations require initialization', () async {
    await expectLater(LinkBud.instance.pending(), throwsStateError);
    await expectLater(LinkBud.instance.reopen('url'), throwsStateError);
  });

  test(
    'final backend configuration keeps API authority and forwards alias results',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/mobile-domain-contract.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final values = fixture['configuration'] as Map<String, dynamic>;
      final configured = LinkBudConfiguration(
        origin: values['link_origin'] as String,
        applicationId: values['application_id'] as String,
        environment: values['environment'] as String,
        sdkId: values['sdk_id'] as String,
        appleAppId: '${values['apple_team_id']}.${values['apple_bundle_id']}',
        additionalLinkHosts: List<String>.from(
          values['additional_link_hosts'] as List,
        ),
      );
      await LinkBud.instance.initialize(configured);
      expect((calls.first.arguments as Map)['origin'], values['link_origin']);
      expect(
        (calls.first.arguments as Map)['additionalLinkHosts'],
        values['additional_link_hosts'],
      );
      response = {
        'status': 'pending',
        'id': 'shared-contract-delivery',
        'destination': (fixture['resolution'] as Map)['destination'],
        'expiresAt': '2027-01-01T00:00:00Z',
      };
      final custom =
          await LinkBud.instance.handleUrl(fixture['custom_url'] as String)
              as PendingDestination;
      final managed =
          await LinkBud.instance.handleUrl(fixture['managed_url'] as String)
              as PendingDestination;
      expect(custom.id, managed.id);
      expect(custom.destination, (fixture['resolution'] as Map)['destination']);
      expect(calls.last.arguments, {'url': fixture['managed_url']});
    },
  );

  test(
    'initialize sends only public config and obtains cold launch result',
    () async {
      expect(await LinkBud.instance.initialize(config), isA<LinkBudEmpty>());
      expect(calls.map((call) => call.method), ['initialize', 'start']);
      expect(calls.first.arguments, config.toMap());
    },
  );

  test('application domain configuration is passed to native SDKs', () {
    const shortConfig = LinkBudConfiguration(
      origin: 'https://links.example.com',
      applicationId: 'aaaaaaaaaaaaaaaaaaaaaaaaaa',
      environment: 'default',
      sdkId: 'bbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    expect(shortConfig.toMap()['origin'], 'https://links.example.com');
    expect(config.toMap().containsKey('routePrefix'), isFalse);
    expect(config.toMap().containsKey('additionalLinkHosts'), isFalse);
  });

  test(
    'additional incoming hosts reach native without replacing API origin',
    () async {
      const configured = LinkBudConfiguration(
        origin: 'https://links.example.com',
        applicationId: 'aaaaaaaaaaaaaaaaaaaaaaaaaa',
        environment: 'default',
        sdkId: 'bbbbbbbbbbbbbbbbbbbbbbbbbb',
        appleAppId: 'A1B2C3D4E5.dev.linkbud.sample',
        additionalLinkHosts: ['go.example.com'],
      );
      await LinkBud.instance.initialize(configured);
      final arguments = calls.first.arguments as Map;
      expect(arguments['origin'], config.origin);
      expect(arguments['additionalLinkHosts'], ['go.example.com']);
      expect(arguments['applicationId'], config.applicationId);
      expect(arguments['sdkId'], config.sdkId);
      expect(arguments.containsKey('managementSecret'), isFalse);
    },
  );

  test('encoded host lists are snapshots rather than mutable references', () {
    final hosts = ['go.example.com'];
    final configured = LinkBudConfiguration(
      origin: config.origin,
      applicationId: config.applicationId,
      environment: config.environment,
      sdkId: config.sdkId,
      additionalLinkHosts: hosts,
    );
    final encoded = configured.toMap();
    hosts[0] = 'other.example.com';
    expect(encoded['additionalLinkHosts'], ['go.example.com']);
    expect(
      () => (encoded['additionalLinkHosts'] as List<String>).add(
        'other.example.com',
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'pending preserves the native delivery identity, path and UTC expiry',
    () async {
      response = {
        'status': 'pending',
        'id': 'native-delivery-id',
        'destination': '/welcome?source=share',
        'expiresAt': '2026-10-27T12:00:00Z',
      };
      final value = await LinkBud.instance.pending() as PendingDestination;
      expect(value.id, 'native-delivery-id');
      expect(value.destination, '/welcome?source=share');
      expect(value.expiresAt, DateTime.utc(2026, 10, 27, 12));
      expect(calls.single.method, 'pending');
    },
  );

  test(
    'resume delegates revalidation without a Dart network or state copy',
    () async {
      response = {'status': 'retryable', 'retryAt': '2026-10-27T12:05:00Z'};
      final value = await LinkBud.instance.resume() as LinkBudRetryable;
      expect(value.retryAt, DateTime.utc(2026, 10, 27, 12, 5));
      expect(calls.single.method, 'resume');
    },
  );

  test(
    'URL input is forwarded unchanged for native boundary validation',
    () async {
      response = {'status': 'rejected', 'reason': 'invalid_link'};
      final value =
          await LinkBud.instance.handleUrl('https://other.test/l/wrong')
              as LinkBudRejected;
      expect(value.reason, 'invalid_link');
      expect(calls.single.arguments, {'url': 'https://other.test/l/wrong'});
    },
  );

  test('manual recovery does not silently alter user input', () async {
    await LinkBud.instance.recover(' ABCD-EF01 ');
    expect(calls.single.method, 'recover');
    expect(calls.single.arguments, {'code': ' ABCD-EF01 '});
  });

  test(
    'explicit reopening delegates validation and preserves native outcomes',
    () async {
      const url = 'https://links.example.com/Ab1/Cd34Ef';
      response = {
        'status': 'pending',
        'id': 'fresh-delivery',
        'destination': '/welcome',
        'expiresAt': '2026-11-12T12:00:00Z',
      };
      expect(
        (await LinkBud.instance.reopen(url) as PendingDestination).id,
        'fresh-delivery',
      );
      expect(calls.single.method, 'reopen');
      expect(calls.single.arguments, {'url': url});
      response = {'status': 'rejected', 'reason': 'pending_destination_exists'};
      expect(
        (await LinkBud.instance.reopen(url) as LinkBudRejected).reason,
        'pending_destination_exists',
      );
      response = {'status': 'alreadyAcknowledged'};
      expect(
        await LinkBud.instance.handleUrl(url),
        isA<LinkBudAlreadyAcknowledged>(),
      );
      expect(calls.last.method, 'handleUrl');
    },
  );

  test('destination failures accept only fixed generic reasons', () async {
    response = true;
    expect(
      await LinkBud.instance.destinationFailed('delivery-id', 'permission'),
      true,
    );
    expect(calls.single.method, 'destinationFailed');
    expect(calls.single.arguments, {
      'id': 'delivery-id',
      'reason': 'permission',
    });
    await expectLater(
      LinkBud.instance.destinationFailed('delivery-id', 'private app details'),
      throwsArgumentError,
    );
    expect(calls.length, 1);
  });

  test('acknowledgment preserves native persistence failure', () async {
    response = false;
    expect(await LinkBud.instance.acknowledge('delivery-id'), false);
    expect(calls.single.arguments, {'id': 'delivery-id'});
    response = true;
    expect(await LinkBud.instance.acknowledge('delivery-id'), true);
  });

  test(
    'already acknowledged and unsupported recovery retain explicit outcomes',
    () async {
      response = {'status': 'alreadyAcknowledged'};
      expect(
        await LinkBud.instance.handleUrl('url'),
        isA<LinkBudAlreadyAcknowledged>(),
      );
      response = {'status': 'rejected', 'reason': 'unsupported_recovery'};
      expect(
        (await LinkBud.instance.recover('code') as LinkBudRejected).reason,
        'unsupported_recovery',
      );
    },
  );

  test('native configuration/operation failures reach the caller', () async {
    failure = PlatformException(code: 'configuration_locked');
    await expectLater(
      LinkBud.instance.initialize(config),
      throwsA(isA<PlatformException>()),
    );
    expect(calls.map((call) => call.method), ['initialize']);
  });

  test('malformed native responses fail closed', () async {
    for (final value in [
      null,
      {'status': 'unknown'},
      {'status': 'pending'},
    ]) {
      response = value;
      await expectLater(LinkBud.instance.pending(), throwsA(anything));
    }
  });

  Future<void> sendIncoming(Object? value) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onResult', value),
          ),
          (_) {},
        );
  }

  test('warm incoming native results reach the stream once', () async {
    final received = <LinkBudResult>[];
    final subscription = LinkBud.instance.incoming.listen(received.add);
    await sendIncoming({
      'status': 'pending',
      'id': 'warm',
      'destination': '/welcome',
      'expiresAt': '2026-10-27T13:00:00Z',
    });
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    expect((received.single as PendingDestination).id, 'warm');
    await subscription.cancel();
  });

  test(
    'invalid incoming data reports an error without a navigation hint',
    () async {
      final errors = <Object>[];
      final subscription = LinkBud.instance.incoming.listen(
        (_) => fail('No destination expected'),
        onError: errors.add,
      );
      await sendIncoming({'status': 'unknown'});
      await Future<void>.delayed(Duration.zero);
      expect(errors.single, isA<FormatException>());
      await subscription.cancel();
    },
  );
}
