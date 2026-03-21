class ChatMessage {
  final String messageId;
  final String senderHash;
  final String receiverHash;
  final String senderType;
  final String messageEncrypted;
  final String? messageDecrypted;
  final DateTime timestamp;
  final bool isFromParent;
  final String senderName;
  final bool isRead;

  ChatMessage({
    required this.messageId,
    required this.senderHash,
    required this.receiverHash,
    required this.senderType,
    required this.messageEncrypted,
    this.messageDecrypted,
    required this.timestamp,
    required this.isFromParent,
    required this.senderName,
    this.isRead = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final senderType =
        (json['sender_type'] ??
                ((json['is_from_parent'] == true) ? 'guardian' : 'child'))
            .toString();
    final isFromParent = senderType == 'guardian' || json['is_from_parent'] == true;

    final rawTimestamp =
        (json['created'] ?? json['timestamp'] ?? DateTime.now().toIso8601String())
            .toString();
    DateTime parsedTimestamp;
    try {
      parsedTimestamp = DateTime.parse(rawTimestamp);
    } catch (_) {
      parsedTimestamp = DateTime.now();
    }

    return ChatMessage(
      messageId: (json['id'] ?? json['message_id'] ?? '').toString(),
      senderHash: (json['sender_hash'] ?? senderType).toString(),
      receiverHash: (json['receiver_hash'] ?? '').toString(),
      senderType: senderType,
      messageEncrypted: (json['message_encrypted'] ?? '').toString(),
      messageDecrypted: json['message_decrypted'],
      timestamp: parsedTimestamp,
      isFromParent: isFromParent,
      senderName: (json['sender_name'] ?? (isFromParent ? 'Guardian' : 'Child')).toString(),
      isRead: json['is_read'] == true,
    );
  }

  ChatMessage copyWith({
    String? messageId,
    String? senderHash,
    String? receiverHash,
    String? senderType,
    String? messageEncrypted,
    String? messageDecrypted,
    DateTime? timestamp,
    bool? isFromParent,
    String? senderName,
    bool? isRead,
  }) {
    return ChatMessage(
      messageId: messageId ?? this.messageId,
      senderHash: senderHash ?? this.senderHash,
      receiverHash: receiverHash ?? this.receiverHash,
      senderType: senderType ?? this.senderType,
      messageEncrypted: messageEncrypted ?? this.messageEncrypted,
      messageDecrypted: messageDecrypted ?? this.messageDecrypted,
      timestamp: timestamp ?? this.timestamp,
      isFromParent: isFromParent ?? this.isFromParent,
      senderName: senderName ?? this.senderName,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': messageId,
      'message_id': messageId,
      'sender_hash': senderHash,
      'receiver_hash': receiverHash,
      'sender_type': senderType,
      'message_encrypted': messageEncrypted,
      'message_decrypted': messageDecrypted,
      'created': timestamp.toIso8601String(),
      'timestamp': timestamp.toIso8601String(),
      'is_from_parent': isFromParent,
      'sender_name': senderName,
      'is_read': isRead,
    };
  }
}
