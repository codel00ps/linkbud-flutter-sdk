import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:linkbud_flutter/linkbud_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff166534)),
      ),
      home: const LinkBudExample(),
    ),
  );
}

class LinkBudExample extends StatefulWidget {
  const LinkBudExample({super.key});
  @override
  State<LinkBudExample> createState() => _LinkBudExampleState();
}

class _LinkBudExampleState extends State<LinkBudExample> {
  final sdk = LinkBud.instance;
  final code = TextEditingController();
  StreamSubscription<LinkBudResult>? subscription;
  String status = 'Initializing public environment configuration…';
  bool signedIn = false;
  bool busy = true;
  bool routing = false;
  String? routedId;

  @override
  void initState() {
    super.initState();
    subscription = sdk.incoming.listen(
      (result) => unawaited(show(result)),
      onError: (_) {
        if (mounted)
          setState(
            () => status = 'Incoming link failed. Reopen the original link.',
          );
      },
    );
    unawaited(
      run(
        () => sdk.initialize(
          const LinkBudConfiguration(
            origin: String.fromEnvironment(
              'LINKBUD_ORIGIN',
              defaultValue: 'https://links.example.com',
            ),
            applicationId: String.fromEnvironment(
              'LINKBUD_APPLICATION',
              defaultValue: 'aaaaaaaaaaaaaaaaaaaaaaaaaa',
            ),
            environment: String.fromEnvironment(
              'LINKBUD_ENVIRONMENT',
              defaultValue: 'default',
            ),
            sdkId: String.fromEnvironment(
              'LINKBUD_SDK_ID',
              defaultValue: 'bbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
            routePrefix: String.fromEnvironment(
              'LINKBUD_ROUTE_PREFIX',
              defaultValue: 'Ab1',
            ),
            appleAppId: String.fromEnvironment(
              'LINKBUD_APPLE_APP_ID',
              defaultValue: 'A1B2C3D4E5.dev.linkbud.sample',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> run(Future<LinkBudResult> Function() operation) async {
    setState(() => busy = true);
    try {
      await show(await operation());
    } catch (_) {
      if (mounted)
        setState(
          () => status =
              'Operation failed. Check setup or retry after the current operation.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> show(LinkBudResult result) async {
    if (!mounted) return;
    switch (result) {
      case PendingDestination():
        if (!signedIn) {
          setState(() => status = 'Destination waiting for simulated login.');
          return;
        }
        if (result.expiresAt.isBefore(DateTime.now().toUtc()) ||
            Uri.parse(result.destination).path != '/welcome') {
          setState(
            () => status =
                'Expired or unsupported route. Only /welcome is allowed in this sample.',
          );
          return;
        }
        if (routing) return;
        routing = true;
        try {
          // Demo only. A real host must authenticate, revalidate and authorize its own routes.
          if (routedId != result.id) {
            routedId = result.id;
            setState(
              () => status = 'Welcome! Simulated authorized navigation.',
            );
          }
          if (!await sdk.acknowledge(result.id) && mounted) {
            setState(
              () => status =
                  'Welcome shown; acknowledgment failed. Retry without navigating twice.',
            );
          }
        } finally {
          routing = false;
        }
      case LinkBudRetryable():
        setState(
          () => status = 'Retry at or after ${result.retryAt.toLocal()}.',
        );
      case LinkBudRejected():
        setState(
          () => status =
              'Cannot continue (${result.reason}). Reopen the link or request a fresh code.',
        );
      case LinkBudAlreadyAcknowledged():
        setState(() => status = 'Journey already handled.');
      case LinkBudEmpty():
        setState(
          () => status = 'No pending destination. Open a configured link.',
        );
    }
  }

  @override
  void dispose() {
    unawaited(subscription?.cancel());
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LinkBud Flutter sample')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Demo login only. Real authentication and route authorization belong to the host app.',
        ),
        const SizedBox(height: 24),
        Text(status, key: const Key('linkbud-status'), semanticsLabel: status),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy
              ? null
              : () {
                  setState(() => signedIn = true);
                  unawaited(run(sdk.resume));
                },
          child: Text(
            signedIn
                ? 'Revalidate pending destination'
                : 'Simulate login and revalidate',
          ),
        ),
        TextButton(
          onPressed: busy ? null : () => unawaited(run(sdk.resume)),
          child: const Text('Retry'),
        ),
        if (Platform.isIOS) ...[
          const SizedBox(height: 24),
          TextField(
            controller: code,
            decoration: const InputDecoration(labelText: 'Recovery code'),
            autocorrect: false,
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    final entered = code.text;
                    code.clear();
                    unawaited(run(() => sdk.recover(entered)));
                  },
            child: const Text('Use entered code'),
          ),
          const Text(
            'Explicit code entry only. No automatic recovery or clipboard reading.',
          ),
        ],
      ],
    ),
  );
}
