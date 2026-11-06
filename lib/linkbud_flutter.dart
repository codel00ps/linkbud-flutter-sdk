import 'dart:async';

import 'package:flutter/services.dart';

/// Public environment identifiers only. Never supply a management credential.
class LinkBudConfiguration {
  const LinkBudConfiguration({
    required this.origin,
    required this.applicationId,
    required this.environment,
    required this.sdkId,
    this.appleAppId,
    this.routePrefix,
  });

  final String origin;
  final String applicationId;
  final String environment;
  final String sdkId;
  final String? appleAppId;
  final String? routePrefix;

  Map<String, String> toMap() => {
    'origin': origin,
    'applicationId': applicationId,
    'environment': environment,
    'sdkId': sdkId,
    if (appleAppId != null) 'appleAppId': appleAppId!,
    if (routePrefix != null) 'routePrefix': routePrefix!,
  };
}

sealed class LinkBudResult {
  const LinkBudResult();

  factory LinkBudResult.fromMap(Map<Object?, Object?> map) {
    switch (map['status']) {
      case 'pending':
        return PendingDestination(
          id: map['id'] as String,
          destination: map['destination'] as String,
          expiresAt: DateTime.parse(map['expiresAt'] as String).toUtc(),
        );
      case 'empty':
        return const LinkBudEmpty();
      case 'alreadyAcknowledged':
        return const LinkBudAlreadyAcknowledged();
      case 'retryable':
        return LinkBudRetryable(
          DateTime.parse(map['retryAt'] as String).toUtc(),
        );
      case 'rejected':
        return LinkBudRejected(map['reason'] as String);
      default:
        throw const FormatException('Unknown native LinkBud result');
    }
  }
}

/// An untrusted navigation hint. Authenticate, revalidate and authorize before use.
final class PendingDestination extends LinkBudResult {
  const PendingDestination({
    required this.id,
    required this.destination,
    required this.expiresAt,
  });
  final String id;
  final String destination;
  final DateTime expiresAt;
}

final class LinkBudEmpty extends LinkBudResult {
  const LinkBudEmpty();
}

final class LinkBudAlreadyAcknowledged extends LinkBudResult {
  const LinkBudAlreadyAcknowledged();
}

final class LinkBudRetryable extends LinkBudResult {
  const LinkBudRetryable(this.retryAt);
  final DateTime retryAt;
}

final class LinkBudRejected extends LinkBudResult {
  const LinkBudRejected(this.reason);
  final String reason;
}

/// One client in the main isolate and one Flutter engine per app process.
/// Native SDKs own persistence, recovery, retries and deduplication.
class LinkBud {
  LinkBud._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onResult') {
        try {
          _results.add(
            LinkBudResult.fromMap(
              Map<Object?, Object?>.from(call.arguments as Map),
            ),
          );
        } catch (error, stack) {
          _results.addError(error, stack);
        }
      }
    });
  }

  static final LinkBud instance = LinkBud._();
  static const _channel = MethodChannel('dev.linkbud/flutter');
  final _results = StreamController<LinkBudResult>.broadcast();
  bool _initialized = false;

  /// Warm incoming link results. Listen before initialize; initialize returns the
  /// cold-link/restart result. After missed events, pending/resume read native state.
  Stream<LinkBudResult> get incoming => _results.stream;

  Future<LinkBudResult> initialize(LinkBudConfiguration configuration) async {
    await _channel.invokeMethod<void>('initialize', configuration.toMap());
    _initialized = true;
    return _result('start');
  }

  Future<LinkBudResult> handleUrl(String url) =>
      _result('handleUrl', {'url': url});

  /// Cached only; call resume after authentication and before delayed navigation.
  Future<LinkBudResult> pending() => _result('pending');

  /// Revalidates pending input. Android also checks Play referrer when appropriate.
  Future<LinkBudResult> resume() => _result('resume');

  /// iOS only, after explicit user entry/paste. Android returns unsupported_recovery.
  Future<LinkBudResult> recover(String code) =>
      _result('recover', {'code': code});

  /// Call only after successful authorized, idempotent host navigation.
  Future<bool> acknowledge(String id) async {
    _requireInitialized();
    return await _channel.invokeMethod<bool>('acknowledge', {'id': id}) ??
        false;
  }

  /// Call only when the destination was abandoned; never send business data.
  Future<bool> destinationFailed(String id, String reason) async {
    _requireInitialized();
    const reasons = {'navigation', 'authentication', 'permission', 'unavailable', 'unsupported'};
    if (!reasons.contains(reason)) throw ArgumentError.value(reason, 'reason');
    return await _channel.invokeMethod<bool>('destinationFailed', {'id': id, 'reason': reason}) ?? false;
  }

  Future<LinkBudResult> _result(
    String method, [
    Map<String, String>? arguments,
  ]) async {
    _requireInitialized();
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    if (map == null)
      throw const FormatException('Missing native LinkBud result');
    return LinkBudResult.fromMap(map);
  }

  void _requireInitialized() {
    if (!_initialized) throw StateError('Initialize LinkBud first');
  }
}
