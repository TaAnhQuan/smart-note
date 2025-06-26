import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:saber/components/asr/stt.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/llm/llm.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/message/chat_message.dart';
import 'package:saber/data/objectbox.g.dart';

class ChatScreen extends StatefulWidget {
  final List<EditorPage> pages;
  final int currentPageIndex;
  final EditorImage? backgroundImage;
  final Uint8List? selectedImageData;
  final int sessionId;
  final VoidCallback? onBackPressed;
  final Store store;

  const ChatScreen(
      {super.key,
      required this.pages,
      required this.currentPageIndex,
      required this.backgroundImage,
      this.selectedImageData,
      required this.sessionId,
      this.onBackPressed,
      required this.store});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  late final Box<ChatMessage> _messageBox;
  Uint8List? _selectedImage;

  // Controller define
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SpeechToTextService _speechToTextService = SpeechToTextService();
  final LLMService _llmService = LLMService();

  @override
  void initState() {
    super.initState();
    _initInputField();
    _initStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    _selectedImage = widget.selectedImageData;
  }

  Future<void> _initStore() async {
    _messageBox = widget.store.box<ChatMessage>();
    _loadSavedMessages();
  }

  void _loadSavedMessages() {
    final queryBuilder = _messageBox
        .query(ChatMessage_.session.equals(widget.sessionId))
      ..order(ChatMessage_.timestamp);
    final query = queryBuilder.build();
    _messages.addAll(query.find());
    query.close();
    setState(() {});
  }

  @override
  void dispose() {
    _speechToTextService.removeListener(_onSpeechToTextChange);
    super.dispose();
  }

  Future<void> _initInputField() async {
    await _speechToTextService.init();
    _speechToTextService.addListener(_onSpeechToTextChange);
  }

  void _onSpeechToTextChange() {
    _controller.text = _speechToTextService.lastWords;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  String _extractFinalAnswer(String? response) {
    if (response == null) {
      return 'No response from LLM';
    }
    final conclusionMarker = '**Conclusion:**';
    final conclusionIndex = response.indexOf(conclusionMarker);
    if (conclusionIndex != -1) {
      String afterConclusion =
          response.substring(conclusionIndex + conclusionMarker.length).trim();
      List<String> paragraphs = afterConclusion.split(RegExp(r'\n\s*\n'));
      if (paragraphs.isNotEmpty) {
        return paragraphs.first.trim();
      }
    }
    return response;
  }

  Future<void> _sendMessage() async {
    final userMessageText = _controller.text.trim();
    if (userMessageText.isEmpty) return;

    print('User text message $userMessageText');
    if (mounted) {
      setState(() {
        final userMessage = ChatMessage(
          text: userMessageText,
          isUser: true,
          image: widget.selectedImageData,
          sessionId: widget.sessionId,
        );
        _messages.add(userMessage);
        _messageBox.put(userMessage);
        _messages.add(ChatMessage(
            text: '...', isUser: false, sessionId: widget.sessionId));
        _selectedImage = null;
      });
    }

    _controller.clear();
    _scrollToBottom();

    print('Try to get response from the LLM');
    try {
      final currentPageStrokes = widget.pages[widget.currentPageIndex].strokes;
      print('Get message from the LLM');
      await _llmService.sendToGemini(
          userMessageText, widget.selectedImageData, currentPageStrokes);

      final response = _extractFinalAnswer(_llmService.llmResponse);
      print('LLM response: $response');
      if (mounted) {
        setState(() {
          _messages.removeLast();
          final botMessage = ChatMessage(
              text: response, isUser: false, sessionId: widget.sessionId);
          _messages.add(botMessage);
          _messageBox.put(botMessage);
        });
      }
    } catch (e) {
      setState(() {
        final botMessage = ChatMessage(
            text: 'Error: ${e.toString()}',
            isUser: false,
            sessionId: widget.sessionId);
        _messages.removeLast();
        _messages.add(botMessage);
        _messageBox.put(botMessage);
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
    final textColor = msg.isUser ? Colors.black87 : Colors.black87;
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
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
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
                crossAxisAlignment: msg.isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (msg.image != null)
                    Container(
                      width: 200,
                      height: 200,
                      margin: EdgeInsets.only(bottom: 8),
                      child: Image.memory(
                        msg.image!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  if (msg.text.isNotEmpty)
                    Text(
                      msg.text,
                      style: TextStyle(color: textColor, fontSize: 16),
                    ),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBackPressed,
        ),
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
                  icon: Icon(
                      _speechToTextService.listening ? Icons.stop : Icons.mic),
                  color:
                      _speechToTextService.listening ? Colors.red : Colors.grey,
                  onPressed: _speechToTextService.available
                      ? () async {
                          await _speechToTextService.toggleListening();
                        }
                      : null,
                  tooltip: _speechToTextService.listening
                      ? 'Stop Listening'
                      : 'Start Listening',
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
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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
