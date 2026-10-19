import 'dart:async';

import 'package:flutter/foundation.dart';

import 'haptic_service.dart';
import 'sound_service.dart';

/// The incoming-order alarm: looping ringtone + haptic pattern, started and
/// stopped as one thing.
///
/// They are bundled deliberately. The two used to be raised separately, and
/// every exit path (accept, reject, expiry, cancellation, another partner
/// claiming it, the alert being dismissed) then had to remember to silence
/// both — one missed call and the rider is left with a phone that keeps
/// buzzing after the order is gone. One start, one stop, nothing to forget.
class OrderAlert {
  OrderAlert._();

  static Timer? _hapticTimer;
  static Timer? _watchdog;

  /// Incremented on every [start]. A [stop] carrying an older token belongs to
  /// an alert that has already been replaced, and is ignored.
  ///
  /// This exists because of back-to-back orders. When one offer replaces
  /// another, Flutter builds the new screen's state before disposing the old
  /// one — so the old `dispose` ran *after* the new `initState` and silenced
  /// the ringtone for an order that had only just arrived. The rider got a
  /// second offer with no sound at all.
  static int _generation = 0;

  /// The pattern pulses rather than vibrating continuously, and stops on its
  /// own after this many pulses even if nothing ever calls [stop] — a runaway
  /// vibration is worse than a missed order.
  static const _maxPulses = 12;
  static const _pulseGap = Duration(milliseconds: 1200);

  /// How long after the offer window the alarm silences itself regardless.
  static const _watchdogGrace = Duration(seconds: 10);

  /// Returns a token to hand back to [stop] from a disposal path.
  ///
  /// Synchronous on purpose: an async token would not be assigned yet if the
  /// widget were disposed in the same frame, which is exactly the race this
  /// token exists to close.
  static int start({required String source, Duration? window}) {
    final token = ++_generation;

    // Re-entrant by design: a second offer replacing the first restarts the
    // alarm rather than stacking a second player/timer on top of it.
    _hapticTimer?.cancel();
    var pulses = 0;
    HapticService.heavy();
    _hapticTimer = Timer.periodic(_pulseGap, (timer) {
      if (++pulses >= _maxPulses) {
        timer.cancel();
        return;
      }
      HapticService.heavy();
    });

    // SoundService keeps a single player and stops it before playing, so this
    // can never produce two overlapping ringtones.
    unawaited(SoundService.playRingtone(source: source));

    // Backstop. Every exit path already stops the alarm; this bounds it if one
    // is ever missed, because a ringtone outliving its order is worse than a
    // missed order.
    _watchdog?.cancel();
    _watchdog = Timer((window ?? const Duration(seconds: 45)) + _watchdogGrace, () {
      debugPrint('[RINGTONE] watchdog fired — forcing silence');
      stop(source: 'OrderAlert.watchdog');
    });

    return token;
  }

  /// Pass [token] only from a disposal path, where the caller may no longer be
  /// the alert that is actually ringing. Accept, reject and expiry stop
  /// unconditionally — they are the user's decision and must always silence it.
  static Future<void> stop({required String source, int? token}) async {
    if (token != null && token != _generation) {
      debugPrint('[RINGTONE] stale stop from $source ignored '
          '(token $token, current $_generation)');
      return;
    }
    _hapticTimer?.cancel();
    _hapticTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
    await SoundService.stopRingtone(source: source);
  }
}
