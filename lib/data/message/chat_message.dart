import 'dart:typed_data';
import 'package:objectbox/objectbox.dart';

@Entity()
class ChatSession {
  @Id()
  int id = 0;
  String title;
  String? lastMessage;
  DateTime? lastTime;

  @Backlink()
  final messages = ToMany<ChatMessage>();

  ChatSession({required this.title});
}

@Entity()
class ChatMessage {
  @Id()
  int id = 0;
  String text;
  bool isUser;
  DateTime timestamp;

  @Property(type: PropertyType.byteVector)
  Uint8List? image;

  final session = ToOne<ChatSession>();

  ChatMessage({
    required this.text,
    required this.isUser,
    this.image,
    DateTime? timestamp,
    int sessionId = 0,
  }) : timestamp = timestamp ?? DateTime.now() {
    if (sessionId != 0) session.targetId = sessionId;
  }
}
