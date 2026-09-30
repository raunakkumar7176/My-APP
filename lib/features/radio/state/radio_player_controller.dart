import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/radio_track.dart';
import '../domain/spoken_script_builder.dart';

enum RadioPlaybackState { idle, playing, paused, buffering }

/// "Radio Mode" — reads a playlist of questions aloud via on-device TTS.
/// A single global `ChangeNotifier` instance (same pattern as every other
/// app-wide service here: `ThemeService`, `NetworkStatusService`), so the
/// persistent mini-player bar can show/react to it from anywhere in the
/// app regardless of which screen started playback, without a second
/// audio session fighting the first.
///
/// Deliberately `flutter_tts` only, no `audio_service` — true background/
/// lock-screen media controls need a real Android foreground service +
/// notification channel + MediaSession wiring, a separate, heavier piece
/// of native setup left for a follow-up; this works fully while the app is
/// in the foreground (any screen, not just the one that started it).
final class RadioPlayerController extends ChangeNotifier {
  RadioPlayerController._();
  static final RadioPlayerController instance = RadioPlayerController._();

  final FlutterTts _tts = FlutterTts();
  bool _ttsInitialized = false;

  List<RadioTrack> _playlist = const [];
  int _currentIndex = 0;
  RadioPlaybackState _state = RadioPlaybackState.idle;
  double _speed = 1.0;
  bool _handsFreeMode = true;
  bool _speakingAnswer = false;
  String? _sourceTitle;

  List<RadioTrack> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  int get totalTracks => _playlist.length;
  RadioPlaybackState get state => _state;
  double get speed => _speed;
  bool get handsFreeMode => _handsFreeMode;
  String? get sourceTitle => _sourceTitle;
  bool get isActive => _state != RadioPlaybackState.idle && _playlist.isNotEmpty;
  bool get isPlaying => _state == RadioPlaybackState.playing || _state == RadioPlaybackState.buffering;

  RadioTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length) ? _playlist[_currentIndex] : null;

  Future<void> _ensureInit() async {
    if (_ttsInitialized) return;
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(_speedToRate(_speed));
    await _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(_onUtteranceDone);
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((msg) {
      AppLogger.warning('RadioPlayerController TTS error: $msg');
    });
    _ttsInitialized = true;
  }

  /// `flutter_tts`'s rate is 0.0-1.0 on Android, not a real "1.0x/1.5x"
  /// multiplier — 0.5 is roughly natural speaking pace on most engines, so
  /// the app's own 1.0x/1.25x/1.5x/2.0x speed chips scale from there
  /// rather than exposing the raw 0-1 value the user would have no
  /// intuition for.
  double _speedToRate(double appSpeed) => (0.5 * appSpeed).clamp(0.1, 1.0);

  void setSpeed(double appSpeed) {
    _speed = appSpeed;
    _tts.setSpeechRate(_speedToRate(_speed));
    notifyListeners();
  }

  void setHandsFreeMode(bool enabled) {
    _handsFreeMode = enabled;
    notifyListeners();
  }

  Future<void> loadPlaylist(
    List<RadioTrack> tracks, {
    int startIndex = 0,
    String? sourceTitle,
  }) async {
    if (tracks.isEmpty) return;
    await _ensureInit();
    _playlist = tracks;
    _currentIndex = startIndex.clamp(0, tracks.length - 1);
    _sourceTitle = sourceTitle;
    _speakingAnswer = false;
    await play();
  }

  Future<void> play() async {
    if (_playlist.isEmpty) return;
    await _ensureInit();
    _state = RadioPlaybackState.playing;
    notifyListeners();
    await _speakCurrentPhrase();
  }

  Future<void> pause() async {
    _state = RadioPlaybackState.paused;
    await _tts.stop();
    notifyListeners();
  }

  Future<void> togglePlayPause() => isPlaying ? pause() : play();

  Future<void> next() async {
    if (_currentIndex >= _playlist.length - 1) {
      await stop();
      return;
    }
    _currentIndex++;
    _speakingAnswer = false;
    if (isPlaying) {
      await _speakCurrentPhrase();
    } else {
      notifyListeners();
    }
  }

  Future<void> previous() async {
    if (_currentIndex <= 0) return;
    _currentIndex--;
    _speakingAnswer = false;
    if (isPlaying) {
      await _speakCurrentPhrase();
    } else {
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    _state = RadioPlaybackState.idle;
    _playlist = const [];
    _currentIndex = 0;
    _speakingAnswer = false;
    _sourceTitle = null;
    notifyListeners();
  }

  /// Speaks a single question immediately, outside any playlist context —
  /// the per-card 🔊 "Suniye" button on the Review screen.
  Future<void> speakOnce(RadioTrack track) async {
    await _ensureInit();
    await _tts.setLanguage(SpokenScriptBuilder.localeFor(track));
    await _tts.speak(SpokenScriptBuilder.questionPhrase(track));
    final answer = SpokenScriptBuilder.answerPhrase(track);
    if (answer != null) {
      await _tts.speak(answer);
    }
  }

  Future<void> _speakCurrentPhrase() async {
    final track = currentTrack;
    if (track == null) {
      await stop();
      return;
    }
    await _tts.setLanguage(SpokenScriptBuilder.localeFor(track));
    notifyListeners();
    if (!_speakingAnswer) {
      await _tts.speak(SpokenScriptBuilder.questionPhrase(track));
    } else {
      final answer = SpokenScriptBuilder.answerPhrase(track);
      if (answer != null) {
        await _tts.speak(answer);
      } else {
        _onUtteranceDone();
      }
    }
  }

  /// Auto-advances the playlist: question → (hands-free pause) → answer →
  /// next question. Never fires once the player has been stopped/paused
  /// out from under an in-flight utterance.
  void _onUtteranceDone() {
    if (_state != RadioPlaybackState.playing) return;
    if (!_speakingAnswer) {
      _speakingAnswer = true;
      if (_handsFreeMode) {
        Timer(const Duration(seconds: 3), () {
          if (_state == RadioPlaybackState.playing) _speakCurrentPhrase();
        });
      } else {
        _speakCurrentPhrase();
      }
    } else {
      _speakingAnswer = false;
      if (_currentIndex >= _playlist.length - 1) {
        stop();
      } else {
        _currentIndex++;
        _speakCurrentPhrase();
      }
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
