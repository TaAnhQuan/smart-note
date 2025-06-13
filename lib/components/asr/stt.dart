import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

typedef SpeechResultCallback = void Function(String recognizedWords);

class SpeechToTextService extends ChangeNotifier{

  bool available = false;
  bool _listening = false;
  String lastWords = '';

  bool get listening => _listening;

  final stt.SpeechToText _speech = stt.SpeechToText();

  Future<void> init() async {
    available = await _initialize(
      onStatus: (status) => debugPrint('STT Status: $status'),
      onError: (e) => debugPrint('STT Error: \$e'),
    );
    notifyListeners();
  }

  Future<bool> _initialize({
    Function(String)? onStatus,
    Function(SpeechRecognitionError)? onError,
  }) async {
    return await _speech.initialize(
      onStatus: onStatus,
      onError: onError,
    );
  }

  Future<void> toggleListening() async {
    if (!available) return;
    if (_listening) {
      await _stopListening();
      _listening = false;
    } else {
      await _startListening((recognizedWords) {
        lastWords = recognizedWords;
        notifyListeners();
      });
      _listening = true;
    }
    notifyListeners();
  }

  Future<void> _startListening(
      SpeechResultCallback onResult, {
        String localeId = 'en_US',
        bool partialResults = true,
      }) async {
    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
      },
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        partialResults: partialResults
      ),
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
  }
}
