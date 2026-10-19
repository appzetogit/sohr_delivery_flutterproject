import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'referral_tracking_service.dart';

/// Receives incoming links and turns them into app state.
///
/// Until now nothing in this app listened for a link at all: the manifest had
/// no VIEW filter, so a shared referral URL opened a browser and the code was
/// lost. This is the missing receiving end.
///
/// Deliberately writes through [ReferralTrackingService] rather than keeping
/// its own copy of the code. That service already feeds the registration form,
/// and it is also where the Play Install Referrer lands -- one store means a
/// rider who arrives by either route is prefilled by the same code path, and
/// the registration screen needs no knowledge of which one they used.
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// Start listening. Safe to call more than once.
  ///
  /// Handles the cold-start link separately from the stream because they are
  /// genuinely different cases: `getInitialLink` is the URI that launched a
  /// dead process, while the stream only fires for links arriving at an app
  /// that is already running. Listening to one and not the other is the usual
  /// reason a link works from the app switcher but not from cold.
  Future<void> initialize() async {
    if (_subscription != null) return;

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handle(initial);
    } catch (e) {
      debugPrint('[DeepLink] initial link failed: $e');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('[DeepLink] stream error: $e'),
    );
  }

  Future<void> _handle(Uri uri) async {
    debugPrint('[DeepLink] received: $uri');
    final code = parseReferralCode(uri);
    if (code == null) return;

    // Never clobber a code the rider already has. The first invite they
    // accepted is the one that should be credited, and a second link -- often
    // just the same rider revisiting their own share -- must not steal it.
    final existing = await ReferralTrackingService.getReferralCode();
    if (existing != null && existing.isNotEmpty) {
      debugPrint('[DeepLink] referral code already stored, keeping "$existing"');
      return;
    }

    await ReferralTrackingService.saveReferralCode(code);
    debugPrint('[DeepLink] stored referral code "$code"');
  }

  /// Pulls a referral code out of an invite link, or null if it is not one.
  ///
  /// Accepts the https form that gets shared and the custom-scheme form used
  /// for local testing. In a custom-scheme URI the first segment arrives as
  /// `host` rather than in `path`, so both are checked.
  ///
  /// `ref` is the documented parameter; `referrer` and `code` are accepted too
  /// because the Play Install Referrer path uses `referrer`, and admins
  /// hand-writing the link template in the panel reach for `code`.
  static String? parseReferralCode(Uri uri) {
    final isReferralPath =
        uri.path.startsWith('/refer') || uri.host == 'refer';
    if (!isReferralPath) return null;

    final q = uri.queryParameters;
    final raw = q['ref'] ?? q['referrer'] ?? q['code'] ?? '';
    final code = raw.trim().toUpperCase();
    return code.isEmpty ? null : code;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
