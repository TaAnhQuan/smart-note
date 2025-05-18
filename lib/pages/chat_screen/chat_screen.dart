import 'package:flutter/material.dart';
import 'package:objectbox/objectbox.dart';
import 'package:saber/components/asr/stt.dart';
import 'package:saber/components/llm/llm.dart';
import 'package:saber/data/message/chat_message.dart';
import 'package:saber/data/objectbox.g.dart';


class ChatScreen extends StatefulWidget {
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

  Future<void> _sendMessage() async {
    final userMessageText = _controller.text.trim();
    if (userMessageText.isEmpty) return;

    print("Send message to LLM");

    // 1) Optimistically show the user’s message
    setState(() {
      final userMessage = ChatMessage(text: userMessageText, isUser: true);

      _messages.add(ChatMessage(text: userMessageText, isUser: true));
      _messageBox.put(userMessage);
      // Optionally show a “typing…” or spinner message until the real reply arrives
      _messages.add(ChatMessage(text: '...', isUser: false, id: 0));
    });

    // clear input and scroll down
    _controller.clear();
    _scrollToBottom();

    try {
      // 2) Actually wait for the network call to finish
      await _llmService.sendToGemini(userMessageText);

      // 3) Grab the real response
      final response = _llmService.llmResponse;

      setState(() {
        // remove the loading placeholder
        _messages.removeLast();

        final botMessage = ChatMessage(text: response, isUser: false);
        // insert the actual bot response
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
    // Remove from ObjectBox
    _messageBox.removeAll();

    // Clear local messages
    setState(() {
      _messages.clear();
    });

    // Optional: Show confirmation snackbar
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
