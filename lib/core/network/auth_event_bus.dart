import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Broadcasts app-wide auth events (e.g. forced logout on refresh failure)
/// so the router and auth state can react without a direct dependency
/// from the networking layer on the auth feature.
class AuthEventBus {
  final _forceLogoutController = StreamController<void>.broadcast();

  final _tokenRefreshedController = StreamController<void>.broadcast();

  Stream<void> get onForceLogout => _forceLogoutController.stream;

  /// Fired after a successful token refresh. The socket checks the token only
  /// at handshake, so it has to reconnect with the new one.
  Stream<void> get onTokenRefreshed => _tokenRefreshedController.stream;

  void emitTokenRefreshed() => _tokenRefreshedController.add(null);

  void emitForceLogout() => _forceLogoutController.add(null);

  void dispose() {
    _forceLogoutController.close();
    _tokenRefreshedController.close();
  }
}

final authEventBusProvider = Provider<AuthEventBus>((ref) {
  final bus = AuthEventBus();
  ref.onDispose(bus.dispose);
  return bus;
});
