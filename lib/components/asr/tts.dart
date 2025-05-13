import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';


class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  Future<void> init() async {
    await _initialize();
  }

  Future<void> _initialize({
    String language = 'en-US',
    double rate = 0.5,
    double volume = 1.0,
    double pitch = 1.0,
  }) async {
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(rate);
    await _tts.setVolume(volume);
    await _tts.setPitch(pitch);
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await _tts.speak(text);
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}