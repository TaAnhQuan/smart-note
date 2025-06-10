import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart' as ml_kit;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:saber/components/asr/stt.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/components/llm/llm.dart';
import 'package:saber/data/message/chat_message.dart';
import 'package:saber/data/objectbox.g.dart';
import 'package:xml/xml.dart';


class ChatScreen extends StatefulWidget {
  final List<EditorPage> pages;
  final int currentPageIndex;
  final EditorImage? backgroundImage;
  final Uint8List? selectedImageData;

  const ChatScreen({
    super.key,
    required this.pages,
    required this.currentPageIndex,
    required this.backgroundImage,
    this.selectedImageData,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  late final Store _store;
  late final Box<ChatMessage> _messageBox;

  // Controller define
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SpeechToTextService _speechToTextService = SpeechToTextService();
  final LLMService _llmService = LLMService();
  final ml_kit.TextRecognizer _textRecognizer = ml_kit.TextRecognizer(script: ml_kit.TextRecognitionScript.latin);

  bool _isRecording = false;

  @override
  void initState(){
    super.initState();
    _initInputField();
    _initStore();
  }

  Future<void> _initStore() async {
    _store = await openStore();
    _messageBox = _store.box<ChatMessage>();
    _loadSavedMessages();
  }

  void _loadSavedMessages(){
    final saved = _messageBox.getAll();
    setState(() {
      _messages.addAll(saved);
      _scrollToBottom();
    });
  }

  @override
  void dispose(){
    _store.close();
    super.dispose();
  }

  Future<void> _initInputField() async{
    await _speechToTextService.init();
    _speechToTextService.addListener((){
      _controller.text = _speechToTextService.lastWords;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  String _extractFinalAnswer(String response) {
    final conclusionMarker = '**Conclusion:**';
    final conclusionIndex = response.indexOf(conclusionMarker);
    if (conclusionIndex != -1) {
      String afterConclusion = response.substring(conclusionIndex + conclusionMarker.length).trim();
      List<String> paragraphs = afterConclusion.split(RegExp(r'\n\s*\n'));
      if (paragraphs.isNotEmpty) {
        return paragraphs.first.trim();
      }
    }
    return response;
  }

  Future<String> _extractBackgroundText() async {
    try {
      if (widget.backgroundImage == null) {
        return '';
      }

      if (widget.backgroundImage!.loadedIn){
        await widget.backgroundImage!.loadIn();
      }

      if (widget.backgroundImage is PngEditorImage){
        return _extractTextFromPng(widget.backgroundImage as PngEditorImage);
      }else if (widget.backgroundImage is PdfEditorImage){
        return _extractTextFromPdf(widget.backgroundImage as PdfEditorImage);
      }else if (widget.backgroundImage is SvgEditorImage){
        return _extractTextFromSvg(widget.backgroundImage as SvgEditorImage);
      }else{
        String errorMessage = 'Unsupported EditorImage type for text extraction';
        debugPrint(errorMessage);
        return '';
      }

    } catch (e) {
      String error = 'Error extracting text: $e';
      debugPrint(error);
      return error;
    }
  }

  Future<String> _extractTextFromPng(PngEditorImage image) async {
    Uint8List? imageBytes = image.thumbnailBytes;

    if (imageBytes == null){
      debugPrint("Could not get image bytes from PngEditorImage.");
      return '';
    }

    final inputImage = ml_kit.InputImage.fromBytes(
        bytes: imageBytes,
        metadata: ml_kit.InputImageMetadata(
            size: image.naturalSize,
            rotation: ml_kit.InputImageRotation.rotation0deg,
            format: ml_kit.InputImageFormat.nv21,
            bytesPerRow: 0
        )
    );

    try{
      final ml_kit.RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      debugPrint("OCR Error (PNG): $e");
      return '';
    }
  }

  Future<String> _extractTextFromPdf(PdfEditorImage image) async {
    try{
      Uint8List? pdfBytes = image.pdfBytes;
      if (pdfBytes == null && image.pdfFile != null){
        pdfBytes = await image.pdfFile!.readAsBytes();
      }

      if (pdfBytes == null){
        debugPrint('No PDF data available to extract text');
        if (image.pdfFile != null){
          final fileBytes = await image.pdfFile!.readAsBytes();
          return await _extractTextFromBytes(fileBytes, image.pdfPage) ?? 'Error extracting text from PDF';
        }
        return '';
      }

      return await _extractTextFromBytes(pdfBytes, image.pdfPage) ?? 'Error extracting text from PDF';
    } catch (e){
      debugPrint('Error extracting text from PDF: $e');
      return 'Error extracting text from PDF';
    }
  }

  Future<String?> _extractTextFromBytes(Uint8List pdfBytes, int pageIndex) async {
    pdfrx.PdfDocument? document;
    try {
      document = await pdfrx.PdfDocument.openData(pdfBytes);
      if (pageIndex >= document.pages.length || pageIndex < 0) {
        debugPrint('Page index $pageIndex is out of range. Document has ${document.pages.length} pages.');
        return null;
      }

      final page = document.pages.elementAt(pageIndex);
      final pageText = await page.loadText();
      return pageText.fullText.trim();

    } catch (e) {
      debugPrint('Error processing PDF page $pageIndex: $e');
      return null;
    } finally {
      document?.dispose();
    }
  }

  Future<String> _extractTextFromSvg(SvgEditorImage image) async{
    String? svgStringContent;
    try{
      svgStringContent = await image.getSvgStringContent();

      if (svgStringContent != null && svgStringContent.isNotEmpty){
        final xmlDocument = XmlDocument.parse(svgStringContent);
        final textElements = xmlDocument.findAllElements('text');
        final tspanElements = xmlDocument.findAllElements('tspan');

        StringBuffer buffer = StringBuffer();
        for (var element in textElements) {
          _extractTextFromXmlElement(element, buffer);
        }
        for (var element in tspanElements) {
          if (element.parentElement?.name.local != 'text' || !textElements.contains(element.parentElement) ) {
            _extractTextFromXmlElement(element, buffer);
          }
        }

        if (buffer.isNotEmpty){
          debugPrint("Successfully extracted text from SVG via XML parsing.");
          return buffer.toString().trim();
        }else{
          debugPrint("No text elements found in SVG via XML parsing. Will try OCR.");
        }
      }
    }catch (e) {
      debugPrint("SVG XML parsing error: $e. Will attempt OCR as fallback.");
    }
    return '';
  }

  void _extractTextFromXmlElement(XmlElement element, StringBuffer buffer) {
    // Iterate over child nodes to capture all text, including those mixed with other elements
    for (var node in element.nodes) {
      if (node is XmlText) {
        if (node.value.trim().isNotEmpty) {
          buffer.writeln(node.value.trim());
        }
      } else if (node is XmlElement) {
        // Recursively extract from child elements like tspan if not handled separately
        // or if specific structure is known (e.g. <text><tspan>...</tspan></text>)
        if (node.name.local == 'tspan') {
          _extractTextFromXmlElement(node, buffer);
        }
      }
    }
  }

  Future<void> _sendMessage() async {
    final userMessageText = _controller.text.trim();
    if (userMessageText.isEmpty) return;

    String pdfText = await _extractBackgroundText();

    setState(() {
      final userMessage = ChatMessage(text: userMessageText, isUser: true);

      _messages.add(ChatMessage(text: userMessageText, isUser: true));
      _messageBox.put(userMessage);
      _messages.add(ChatMessage(text: '...', isUser: false, id: 0));
    });

    _controller.clear();
    _scrollToBottom();

    try {
      final currentPageStrokes = widget.pages[widget.currentPageIndex].strokes;

      await _llmService.sendToGemini(userMessageText, widget.selectedImageData, currentPageStrokes);

      final response = _extractFinalAnswer(_llmService.llmResponse);

      setState(() {
        _messages.removeLast();

        final botMessage = ChatMessage(text: response, isUser: false);
        _messages.add(ChatMessage(text: response, isUser: false));
        _messageBox.put(botMessage);
      });
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(ChatMessage(
          text: 'Error: ${e.toString()}',
          isUser: false,
        ));
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 60,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildMessage(ChatMessage msg) {
    final alignment = msg.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bgColor = msg.isUser ? Colors.blue.shade100 : Colors.grey.shade200;
    final textColor = msg.isUser
        ? Colors.black87
        : Colors.black87;
    final borderRadius = msg.isUser
        ? BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(16),
      bottomLeft: Radius.circular(16),
    )
        : BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(16),
      bottomRight: Radius.circular(16),
    );
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: msg.isUser ? bgColor : bgColor,
              borderRadius: borderRadius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(msg.text, style: TextStyle(color: textColor, fontSize: 16)),
                  SizedBox(height: 4),
                  Text(
                    "${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteAllMessages() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear History'),
        content: Text('Are you sure you want to delete all chat history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAllChatHistory();
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllChatHistory() async {
    _messageBox.removeAll();

    setState(() {
      _messages.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('All chat history cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Assistant'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(Icons.delete_forever),
            onPressed: _confirmDeleteAllMessages,
            tooltip: 'Clear chat history',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (_, index) => _buildMessage(_messages[index]),
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.mic),
                  color: _isRecording ? Colors.red : Colors.grey,
                  onPressed: () async {
                    setState(() {
                      _isRecording = !_isRecording;
                    });
                    if (_isRecording == true){
                      await _speechToTextService.toggleListening();
                    }
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      fillColor: Colors.white,
                      filled: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: Color(0xFF10A37F)),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
