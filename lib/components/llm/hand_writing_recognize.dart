import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as writing_kit;
import 'package:saber/components/canvas/_stroke.dart' as canvas;

class HandwritingRecognition {
  final String _languageCode = 'en-US';
  late final writing_kit.DigitalInkRecognizer _digitalInkRecognizer;
  late final writing_kit.DigitalInkRecognizerModelManager _modelHandWritingManager;
  final ValueNotifier<double> downloadProgress = ValueNotifier(0);
  final ValueNotifier<bool> isBusy = ValueNotifier(false);
  final ValueNotifier<String> recognizedText = ValueNotifier('');
  final ValueNotifier<String?> modelStatusMessage = ValueNotifier(null);

  static final HandwritingRecognition _instance = HandwritingRecognition._internal();
  factory HandwritingRecognition() => _instance;

  HandwritingRecognition._internal();

  Future<void> initialize() async {
    _digitalInkRecognizer = writing_kit.DigitalInkRecognizer(languageCode: _languageCode);
    _modelHandWritingManager = writing_kit.DigitalInkRecognizerModelManager();
    await _ensureModelDownloaded();
  }

  Future<void> _ensureModelDownloaded() async {
    // debugPrint("Downloading the model");
    modelStatusMessage.value = 'Downloading model...';
    try {
      if (!await _modelHandWritingManager.isModelDownloaded(_languageCode)) {
        await _modelHandWritingManager.downloadModel(
          _languageCode,
          // optionally track progress if supported
        );
      }
      modelStatusMessage.value = 'Model ready';
      // debugPrint("Download finish");
    } catch (e) {
      modelStatusMessage.value = 'Model download failed: $e';
      // debugPrint(modelStatusMessage.value);
      rethrow;
    }
  }

  List<writing_kit.Stroke> convertToMlKitStrokes(List<canvas.Stroke> userStrokes) {
    List<writing_kit.Stroke> mlKitStrokes = [];
    int currentTime = 0;
    const timeInterval = 10;
    const strokeInterval = 100;

    for (final stroke in userStrokes){
      final mlStroke = writing_kit.Stroke();
      for (int i = 0; i < stroke.points.length; i++){
        final point = stroke.points[i];
        final timestamp = currentTime + i * timeInterval;
        mlStroke.points.add(writing_kit.StrokePoint(
          x: point.dx,
          y: point.dy,
          t: timestamp
        ));
      }
      mlKitStrokes.add(mlStroke);
      currentTime += stroke.points.length * timeInterval + strokeInterval;
    }

    return mlKitStrokes;
  }

  Future<void> recognizeHandWriting(List<canvas.Stroke> userStrokes) async{
    if (isBusy.value) {
      // debugPrint('Recognizer is busy');
      return;
    }
    if (userStrokes.isEmpty) {
      // debugPrint('No ink to recognize');
      return;
    }

    isBusy.value = true;
    recognizedText.value = 'Recognizing';

    final ink = writing_kit.Ink();
    ink.strokes = convertToMlKitStrokes(userStrokes);

    try {
      final List<writing_kit.RecognitionCandidate> candidates = await _digitalInkRecognizer.recognize(ink);

      if (candidates.isNotEmpty){
        recognizedText.value = candidates.first.text;
      } else {
        recognizedText.value = 'No recognition result';
      }
    } catch (e) {
      debugPrint('Error recognizing ink: $e');
      recognizedText.value = 'Recognition failed';
    } finally {
      isBusy.value = false;
    }
  }

  void clear(){
    recognizedText.value = '';
  }

  void dispose(){
    _digitalInkRecognizer.close();
  }
}
