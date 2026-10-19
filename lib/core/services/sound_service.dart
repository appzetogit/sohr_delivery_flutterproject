import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays short sound effects. Falls back to silence (no crash) if the
/// requested asset hasn't been added to assets/sounds/ yet.
///
/// Uses two players so a short tap sound doesn't cut off a longer
/// machine/ambient effect playing at the same time.
class SoundService {
  static final AudioPlayer _tapPlayer = AudioPlayer();
  static final AudioPlayer _effectsPlayer = AudioPlayer();
  static final AudioPlayer _ringtonePlayer = AudioPlayer();

  /// Short UI feedback sounds, e.g. `SoundService.playTap('printtab.mp3')`
  /// for a file at assets/sounds/printtab.mp3.
  static Future<void> playTap(String assetFileName) async {
    try {
      await _tapPlayer.stop();
      await _tapPlayer.play(AssetSource('sounds/$assetFileName'));
    } catch (_) {
      // Sound asset not available yet — fail silently.
    }
  }

  /// Longer effects, e.g. `SoundService.playEffect('refferticketcomeout.mp3')`
  /// for a file at assets/sounds/refferticketcomeout.mp3.
  static Future<void> playEffect(String assetFileName) async {
    try {
      await _effectsPlayer.stop();
      await _effectsPlayer.play(AssetSource('sounds/$assetFileName'));
    } catch (_) {
      // Sound asset not available yet — fail silently.
    }
  }

  static Future<void> stopEffect() async {
    try {
      await _effectsPlayer.stop();
    } catch (_) {}
  }

  /// Rings on the alarm stream rather than the media one, so a new order is
  /// still audible when the rider has media volume turned down — the normal
  /// state for someone riding with the phone mounted.
  static final AudioContext _ringtoneContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.alarm,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      stayAwake: true,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.duckOthers},
    ),
  );

  /// The incoming-order ringtone, relative to assets/ — [AssetSource] adds the
  /// `assets/` prefix itself. Named here rather than inline so swapping the
  /// file is a one-line change. The old asset (tujh_bin1.mp3) was deleted from
  /// the tree, which broke the alert with "Unable to load asset" until the
  /// logging below surfaced it.
  static const _ringtoneAsset = 'sounds/neworder_ring.mp4';

  /// True between [playRingtone] and [stopRingtone]. Used only to keep the log
  /// honest about whether a stop actually silenced something.
  static bool _ringtonePlaying = false;

  /// Bumped by every play AND every stop, to cancel a play that is still in
  /// flight.
  ///
  /// [playRingtone] is not atomic — it awaits four platform calls before the
  /// sound actually starts, which measured ~840ms on device. A stop arriving
  /// inside that window found nothing playing, did nothing, and then `play()`
  /// completed behind it and looped forever with nothing left to stop it. That
  /// is exactly what happened on accept: the alarm was silenced at 38.857 and
  /// started at 39.000.
  static int _ringtoneSeq = 0;

  static bool get isRingtonePlaying => _ringtonePlaying;

  /// Every ringtone transition is logged under this tag. It loops until
  /// stopped, so when it won't shut up the log says exactly who started it and
  /// whether a stop ever ran: `adb logcat | grep RINGTONE`.
  static void _log(String message) => debugPrint('[RINGTONE] $message');

  /// Looping ringtone for the incoming-order alert. Plays until
  /// [stopRingtone] — accept, reject and countdown-expiry all stop it.
  ///
  /// [source] names the caller — the full-screen order screen and the overlay
  /// bubble run in different isolates with their own player, so when it rings
  /// twice or won't stop, the log has to say which one.
  static Future<void> playRingtone({String source = 'unknown'}) async {
    final seq = ++_ringtoneSeq;
    _log('play requested by $source (already playing: $_ringtonePlaying)');

    /// True once a stop — or a newer play — has superseded this one.
    bool superseded() => seq != _ringtoneSeq;

    try {
      await _ringtonePlayer.stop();
      if (superseded()) return _log('play by $source cancelled before setup');
      await _ringtonePlayer.setAudioContext(_ringtoneContext);
      if (superseded()) return _log('play by $source cancelled before loop mode');
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(1.0);
      if (superseded()) return _log('play by $source cancelled before start');
      await _ringtonePlayer.play(AssetSource(_ringtoneAsset));

      // Checked again AFTER play: a stop can land during play() itself, and by
      // then the loop is running, so it has to be undone rather than skipped.
      if (superseded()) {
        await _ringtonePlayer.stop();
        return _log('play by $source started late and was undone');
      }
      _ringtonePlaying = true;
      _log('playing $_ringtoneAsset (looping) — started by $source');
    } catch (e, s) {
      // Never let a missing or undecodable asset take down the order alert —
      // but say so. Swallowing this silently is how a dead ringtone survives.
      _ringtonePlaying = false;
      _log('FAILED to start: $e');
      debugPrintStack(stackTrace: s, label: '[RINGTONE]');
    }
  }

  static Future<void> stopRingtone({String source = 'unknown'}) async {
    // Invalidates any play still working through its await chain, so it can
    // never start behind this stop.
    _ringtoneSeq++;
    _log('stop requested by $source (was playing: $_ringtonePlaying)');
    try {
      await _ringtonePlayer.stop();
      _ringtonePlaying = false;
      _log('stopped by $source');
    } catch (e) {
      _log('FAILED to stop: $e');
    }
  }

  /// The built-in platform click sound — needs no asset file.
  static void tapClick() {
    SystemSound.play(SystemSoundType.click);
  }

  /// Refresh sound effect
  static Future<void> playRefresh() async {
    try {
      await _tapPlayer.stop();
      await _tapPlayer.play(AssetSource('sounds/refersh.mp4'));
    } catch (_) {
      // Sound asset not available yet — fail silently.
    }
  }
}
