import 'package:flutter/material.dart';
import 'package:saber/components/asr/stt.dart';
import 'package:saber/components/llm/llm.dart';
import 'package:saber/data/message/chat_message.dart';


class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SpeechToTextService _speechToTextService = SpeechToTextService();
  final LLMService _llmService = LLMService();

  bool _isRecording = false;

  @override
  void initState(){
    super.initState();
    _initInputField();
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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // 1) Optimistically show the user’s message
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      // Optionally show a “typing…” or spinner message until the real reply arrives
      _messages.add(ChatMessage(text: '...', isUser: false));
    });

    // clear input and scroll down
    _controller.clear();
    _scrollToBottom();

    try {
      // 2) Actually wait for the network call to finish
      await _llmService.sendToGemini(text);

      // 3) Grab the real response
      final response = _llmService.llmResponse;

      setState(() {
        // remove the loading placeholder
        _messages.removeLast();
        // insert the actual bot response
        _messages.add(ChatMessage(text: response, isUser: false));
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

    // scroll again now that bot message is in
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
    final bgColor = msg.isUser ? Colors.white : Colors.white;
    final textColor = Colors.black87;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.chat_bubble_outline, color: Color(0xFF10A37F)),
            ),
            SizedBox(width: 8),
            Text('ChatGPT Clone', style: TextStyle(color: Colors.white)),
          ],
        ),
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
                  onPressed: (){
                    _speechToTextService.listening;
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
