/// Native LinkBud resolution, explicit recovery and persisted journey handling.
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// Public environment identifiers only. Never supply a management credential.
class LinkBudConfiguration {
  /// Creates a configuration; native initialization validates and locks it.
  const LinkBudConfiguration({
    required this.origin,
    required this.applicationId,
    required this.environment,
    required this.sdkId,
    this.appleAppId,
    this.routePrefix,
  });

  /// Root HTTPS origin hosting this application's LinkBud links.
  final String origin;

  /// Public 26-character application identifier.
  final String applicationId;

  /// Application environment. The supported value is `default`.
  final String environment;

  /// Public 26-character SDK identifier, never a management credential.
  final String sdkId;

  /// Apple team ID and bundle ID, required on iOS and ignored on Android.
  final String? appleAppId;

  /// Immutable, case-sensitive three-character prefix enabling short links.
  final String? routePrefix;

  /// Encodes public configuration for the native method channel.
  Map<String, String> toMap() => {
    'origin': origin,
    'applicationId': applicationId,
    'environment': environment,
    'sdkId': sdkId,
    if (appleAppId != null) 'appleAppId': appleAppId!,
    if (routePrefix != null) 'routePrefix': routePrefix!,
  };
}

/// Outcome of a native journey operation; only pending results carry a route.
sealed class LinkBudResult {
  /// Base constructor for native operation outcomes.
  const LinkBudResult();

  /// Decodes a native result, throwing on an unknown or malformed payload.
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
  /// Creates a navigation hint that still requires host authorization.
  const PendingDestination({
    required this.id,
    required this.destination,
    required this.expiresAt,
  });

  /// Native delivery identity used for idempotent navigation and acknowledgment.
  final String id;

  /// Untrusted application-relative route, including any destination query.
  final String destination;

  /// UTC deadline after which this hint must not be used.
  final DateTime expiresAt;
}

/// No pending journey is available.
final class LinkBudEmpty extends LinkBudResult {
  /// Creates an empty outcome.
  const LinkBudEmpty();
}

/// This journey was already completed; duplicate callbacks must not route.
final class LinkBudAlreadyAcknowledged extends LinkBudResult {
  /// Creates a duplicate-delivery outcome.
  const LinkBudAlreadyAcknowledged();
}

/// A transient failure retained native input for a later retry.
final class LinkBudRetryable extends LinkBudResult {
  /// Creates a retry outcome with the earliest permitted retry time.
  const LinkBudRetryable(this.retryAt);

  /// Earliest UTC time to call [LinkBud.resume] again.
  final DateTime retryAt;
}

/// The operation cannot produce a destination; never navigate from this result.
final class LinkBudRejected extends LinkBudResult {
  /// Creates a rejection with a native, non-sensitive reason code.
  const LinkBudRejected(this.reason);

  /// Reason code such as `invalid_link` or `pending_destination_exists`.
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

  /// The app's single main-isolate LinkBud client.
  static final LinkBud instance = LinkBud._();
  static const _channel = MethodChannel('dev.linkbud/flutter');
  final _results = StreamController<LinkBudResult>.broadcast();
  bool _initialized = false;

  /// Warm incoming link results. Listen before initialize; initialize returns the
  /// cold-link/restart result. After missed events, pending/resume read native state.
  Stream<LinkBudResult> get incoming => _results.stream;

  /// Locks native configuration and returns the cold-link or restart result.
  /// Subscribe to [incoming] first. Native setup and storage errors propagate.
  Future<LinkBudResult> initialize(LinkBudConfiguration configuration) async {
    await _channel.invokeMethod<void>('initialize', configuration.toMap());
    _initialized = true;
    return _result('start');
  }

  /// Validates host-supplied URL input, retaining normal callback deduplication.
  Future<LinkBudResult> handleUrl(String url) =>
      _result('handleUrl', {'url': url});

  /// Explicitly reopens a completed URL as a fresh, server-validated journey.
  /// Use only for a deliberate user action, never for duplicate OS callbacks.
  /// Resume an existing journey with [resume] instead of replacing it.
  Future<LinkBudResult> reopen(String url) => _result('reopen', {'url': url});

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
    const reasons = {
      'navigation',
      'authentication',
      'permission',
      'unavailable',
      'unsupported',
    };
    if (!reasons.contains(reason)) {
      throw ArgumentError.value(reason, 'reason');
    }
    return await _channel.invokeMethod<bool>('destinationFailed', {
          'id': id,
          'reason': reason,
        }) ??
        false;
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
    if (map == null) {
      throw const FormatException('Missing native LinkBud result');
    }
    return LinkBudResult.fromMap(map);
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw StateError('Initialize LinkBud first');
    }
  }
}
