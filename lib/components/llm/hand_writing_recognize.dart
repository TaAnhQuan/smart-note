// import 'dart:async';
// import 'dart:math';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as ml_kit;
//
// class HandwritingRecognitionService {
//   final String _languageCode = 'en-US';
//   late final ml_kit.DigitalInkRecognizer _digitalInkRecognizer;
//   late final ml_kit.DigitalInkRecognizerModelManager _modelManager;
//   final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);
//   final ValueNotifier<bool> isBusy = ValueNotifier(false);
//   String recognizedText = '';
//   final ValueNotifier<String?> modelStatusMessage = ValueNotifier(null);
//
//   HandwritingRecognitionService() {
//     _digitalInkRecognizer = ml_kit.DigitalInkRecognizer(languageCode: _languageCode);
//     _modelManager = ml_kit.DigitalInkRecognizerModelManager();
//   }
//
//   static Future<HandwritingRecognitionService> create() async {
//     final service = HandwritingRecognitionService();
//     await service._ensureModelDownloaded();
//     return service;
//   }
//
//   Future<void> _ensureModelDownloaded() async {
//     modelStatusMessage.value = 'Downloading model...';
//     try {
//       if (!await _modelManager.isModelDownloaded(_languageCode)) {
//         await _modelManager.downloadModel(
//           _languageCode,
//           // optionally track progress if supported
//         );
//       }
//       modelStatusMessage.value = 'Model ready';
//     } catch (e) {
//       modelStatusMessage.value = 'Model download failed: $e';
//       rethrow;
//     }
//   }
//
//   List<ml_kit.Stroke> convertToMlKitStrokes(List<stroke.Stroke> userStrokes) {
//     List<ml_kit.Stroke> mlKitStrokes = [];
//
//     for (var customStroke in userStrokes) {
//       // Skip eraser strokes, as they are not needed for recognition
//       if (!customStroke.isEraser) {
//         // Initialize an empty list to store the StrokePoint objects for this stroke
//         List<ml_kit.StrokePoint> mlKitPoints = [];
//
//         // Iterate over each TimedPoint in the custom Stroke's timedPoints
//         for (var timedPoint in customStroke.createdAt) {
//           // Create a new StrokePoint with x, y from offset and t from timestamp
//           mlKitPoints.add(ml_kit.StrokePoint(
//             x: timedPoint.offset.dx,
//             y: timedPoint.offset.dy,
//             t: timedPoint.timestamp,
//           ));
//         }
//
//         ml_kit.Stroke temp = ml_kit.Stroke();
//         temp.points = mlKitPoints;
//         mlKitStrokes.add(temp);
//       }
//     }
//
//     return mlKitStrokes;
//   }
//
//   Future<void> recognizeHandWriting(List<stroke.Stroke> userStrokes) async{
//     print("Recognize hand writing");
//     if (userStrokes.isEmpty){
//       print("Recognizer busy or no ink to recognize");
//     }
//
//     isBusy.value = true;
//     recognizedText = 'Recognizing...';
//     final ink = ml_kit.Ink();
//     ink.strokes = convertToMlKitStrokes(userStrokes);
//
//     try{
//       final List<ml_kit.RecognitionCandidate> candidates = await _digitalInkRecognizer.recognize(ink);
//
//       if (candidates.isNotEmpty){
//         recognizedText = candidates.first.text;
//         print("Recognition successful: $recognizedText");
//       }else{
//         recognizedText = "No recognition result";
//         print("Recognition returned no candidates");
//       }
//     }catch (e){
//       print("Error recognizing ink: $e");
//       recognizedText = "Recognition failed";
//     }finally{
//       isBusy.value = false;
//     }
//   }
//
//   void clear(){
//     recognizedText = "";
//   }
//
//   void dispose(){
//     _digitalInkRecognizer.close();
//   }
// }