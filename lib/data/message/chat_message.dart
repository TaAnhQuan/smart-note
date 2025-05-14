import 'package:objectbox/objectbox.dart';

@Entity()
class ChatMessage {
  int id;
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    this.id = 0,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}