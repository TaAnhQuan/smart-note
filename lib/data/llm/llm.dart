import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:saber/components/asr/tts.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/llm/hand_writing_recognize.dart';

class LLMService with ChangeNotifier {
  String llmResponse = '';
  final _GEMINI_API_KEY = dotenv.env['GEMINI_API_KEY'] ?? 'default_key';

  final HandwritingRecognition _handwritingRecognitionService = HandwritingRecognition();
  final TtsService _ttsService = TtsService();

  Future<void> sendToGemini(String inputText, List<Stroke> strokes) async {
    try {
      notifyListeners();

      if (_GEMINI_API_KEY.isEmpty) {
        throw 'Missing Gemini API Key';
      }

      // Recognize handwriting from strokes
      await _handwritingRecognitionService.recognizeHandWriting(strokes);
      final handWritingToText = _handwritingRecognitionService.recognizedText.value;

      // Construct payload
      final payload = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': inputText},
              {'text': handWritingToText}
            ]
          }
        ]
      });

      final response = await http
          .post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_GEMINI_API_KEY'),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);

        final candidates = jsonResponse['candidates'];

        if (candidates != null && candidates.isNotEmpty) {
          // Make sure that the nested extraction matches the real API response
          llmResponse = candidates[0]['content'] != null
              ? candidates[0]['content']['parts'][0]['text'] ??
              'No description available'
              : candidates[0]['text'] ?? 'No description available';
        } else {
          throw 'No valid response from API';
        }
      } else {
        throw 'API Error: ${response.statusCode}\n${response.body}';
      }
    } on http.ClientException catch (e) {
      llmResponse = 'Network error: ${e.message}';
    } on TimeoutException {
      llmResponse = 'Request timed out';
    } catch (e) {
      llmResponse = 'Error: ${e.toString()}';
    } finally {
      notifyListeners();
    }
  }
}
