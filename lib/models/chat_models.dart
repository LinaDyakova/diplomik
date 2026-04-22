import 'package:flutter/material.dart';

class ChatModel {
  final int id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final bool isGroup;
  final String? groupName;
  final String? groupPhotoUrl;
  final List<ChatParticipant> participants;
  final int unreadCount;
  final String type; 

  ChatModel({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
    this.lastMessageAt,
    required this.isGroup,
    this.groupName,
    this.groupPhotoUrl,
    required this.participants,
    required this.unreadCount,
    required this.type,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    final typeValue = json['type'] as String? ?? 
        (json['is_group'] == true ? 'group' : 'private');
    return ChatModel(
      id: json['id'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      lastMessage: json['last_message'],
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'])
          : null,
      isGroup: json['is_group'] ?? false,
      groupName: json['group_name'],
      groupPhotoUrl: json['group_photo_url'],
      participants: json['participants'] != null
          ? (json['participants'] as List)
              .map((p) => ChatParticipant.fromJson(p))
              .toList()
          : [],
      unreadCount: json['unread_count'] ?? 0,
      type: typeValue,
    );
  }

  String getDisplayName(String currentUserId) {
    if (type == 'channel') {
      return groupName ?? 'Канал';
    } else if (type == 'group') {
      return groupName ?? 'Групповой чат';
    } else {
      final otherParticipant = participants.firstWhere(
        (p) => p.userId != currentUserId,
        orElse: () => participants.isNotEmpty ? participants.first : ChatParticipant.empty(),
      );
      return '@${otherParticipant.username}';
    }
  }

  IconData getIcon() {
    switch (type) {
      case 'channel':
        return Icons.mic;
      case 'group':
        return Icons.group;
      default:
        return Icons.person;
    }
  }

  String? getAvatarUrl(String currentUserId) {
    if (type == 'channel' || type == 'group') {
      return groupPhotoUrl;
    } else {
      final otherParticipant = participants.firstWhere(
        (p) => p.userId != currentUserId,
        orElse: () => participants.isNotEmpty ? participants.first : ChatParticipant.empty(),
      );
      return otherParticipant.avatarUrl;
    }
  }
}

class ChatParticipant {
  final String userId;
  final String username;
  final String? avatarUrl;
  final DateTime joinedAt;
  final int unreadCount;

  ChatParticipant({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.joinedAt,
    required this.unreadCount,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      userId: json['user_id'],
      username: json['username'] ?? 'Пользователь',
      avatarUrl: json['avatar_url'],
      joinedAt: DateTime.parse(json['joined_at']),
      unreadCount: json['unread_count'] ?? 0,
    );
  }

  static ChatParticipant empty() {
    return ChatParticipant(
      userId: '',
      username: '',
      joinedAt: DateTime.now(),
      unreadCount: 0,
    );
  }
}

class MessageModel {
  final int id;
  final int chatId;
  final String senderId;
  final String content;
  final String messageType;
  final String? imageUrl;
  final int? eventId;
  final DateTime createdAt;
  final bool isRead;

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.messageType = 'text',
    this.imageUrl,
    this.eventId,
    required this.createdAt,
    required this.isRead,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'],
      chatId: json['chat_id'],
      senderId: json['sender_id'],
      content: json['content'],
      messageType: json['message_type'] ?? 'text',
      imageUrl: json['image_url'],
      eventId: json['event_id'],
      createdAt: DateTime.parse(json['created_at']),
      isRead: json['is_read'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chat_id': chatId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType,
      'image_url': imageUrl,
      'event_id': eventId,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
    };
  }
}