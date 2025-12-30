class ChatMessage {
  final String messageId;
  final String senderHash;
  final String receiverHash;
  final String messageEncrypted;
  final String? messageDecrypted;
  final DateTime timestamp;
  final bool isFromParent;
  final String senderName;

  ChatMessage({
    required this.messageId,
    required this.senderHash,
    required this.receiverHash,
    required this.messageEncrypted,
    this.messageDecrypted,
    required this.timestamp,
    required this.isFromParent,
    required this.senderName,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: json['message_id'].toString(),
      senderHash: json['sender_hash'] ?? '',
      receiverHash: json['receiver_hash'] ?? '',
      messageEncrypted: json['message_encrypted'] ?? '',
      messageDecrypted: json['message_decrypted'],
      timestamp: DateTime.parse(json['timestamp']),
      isFromParent: json['is_from_parent'] ?? false,
      senderName: json['sender_name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'sender_hash': senderHash,
      'receiver_hash': receiverHash,
      'message_encrypted': messageEncrypted,
      'message_decrypted': messageDecrypted,
      'timestamp': timestamp.toIso8601String(),
      'is_from_parent': isFromParent,
      'sender_name': senderName,
    };
  }
}
