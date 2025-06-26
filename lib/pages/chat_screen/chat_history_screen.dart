import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/message/chat_message.dart';
import 'package:saber/data/objectbox.g.dart';
import 'package:saber/pages/chat_screen/chat_screen.dart';
import 'package:screenshot/screenshot.dart';

class ChatHistoryScreen extends StatefulWidget {
  final List<EditorPage> pages;
  final int currentPageIndex;
  final EditorImage? backgroundImage;
  final Uint8List? selectedImageData;

  const ChatHistoryScreen({
    super.key,
    required this.pages,
    required this.currentPageIndex,
    required this.backgroundImage,
    this.selectedImageData,
  });


  @override
  _ChatHistoryScreenState createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  final List<ChatSession> _sessions = [];
  late final Store _store;
  late final Box<ChatSession> _sessionBox;
  bool _initialized = false;
  int? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    print('Init state chat history');
    _initStore();
  }

  Future<void> _initStore() async {
    _store = await openStore();
    _sessionBox = _store.box<ChatSession>();
    _loadSavedSessions();
    print('Inside init store function');
    setState(() => _initialized = true);
  }

  void _loadSavedSessions() {
    final saved = _sessionBox.getAll();
    _sessions
      ..clear()
      ..addAll(saved);
  }

  @override
  void dispose() {
    _store.close();
    super.dispose();
  }
  
  void _deleteSession(int id){
    _sessionBox.remove(id);
    setState(() {
      _sessions.removeWhere((session) => session.id == id);
    });
  }
  
  void _addSession(){
    final newSession = ChatSession(title: 'Session ${DateTime.now()}');
    _sessionBox.put(newSession);
    setState(() {
      _sessions.add(newSession);
      _selectedSessionId = newSession.id;
    });
  }

  Future<void> _showRenameDialog(int sessionId) async {
    final session = _sessions.firstWhere((s) => s.id == sessionId);
    final controller = TextEditingController();
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Session'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'New name....',
          ), 
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop(controller.text);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      session.title = newTitle;
      _sessionBox.put(session);
      setState(() {}); // Trigger to rebuild the screen
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Chat Sessions'),
            automaticallyImplyLeading: false,
            actions: [
              if (_selectedSessionId == null)
                IconButton(
                  icon: const Icon(Icons.note_add),
                  onPressed: _addSession,
                ),
            ],
          ),
          body: _sessions.isEmpty
              ? const Center(child: Text('No chat sessions.'))
              : ListView.builder(
            itemCount: _sessions.length,
            itemBuilder: (context, index) {
              final session = _sessions[index];
              return ListTile(
                title: Row(
                  children: [
                    Expanded(child: Text(session.title)),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showRenameDialog(session.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteSession(session.id),
                    ),
                  ],
                ),
                subtitle: session.messages.isNotEmpty
                    ? Text(
                  session.messages.last.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
                    : const Text('Empty session'),
                trailing: session.messages.isNotEmpty
                    ? Text(
                  TimeOfDay.fromDateTime(
                      session.messages.last.timestamp)
                      .format(context),
                )
                    : null,
                onTap: () => setState(() => _selectedSessionId = session.id),
              );
            },
          ),
        ),

        if (_selectedSessionId != null)
          Positioned.fill(
            child: ChatScreen(
              pages: widget.pages,
              currentPageIndex: widget.currentPageIndex,
              backgroundImage: widget.backgroundImage,
              selectedImageData: widget.selectedImageData,
              sessionId: _selectedSessionId!,
              store: _store,
              onBackPressed: () => setState(() => _selectedSessionId = null),
            ),
          ),
      ],
    );
  }
}
