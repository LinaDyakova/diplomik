import 'package:flutter/material.dart';

class NotificationModel {
  final int id;
  final String userId;
  final String actorId;
  final String type; 
  final int? postId;
  final int? commentId;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? actorProfile;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.actorId,
    required this.type,
    this.postId,
    this.commentId,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.actorProfile,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    try {
      print('Parsing notification JSON: $json');
      
      return NotificationModel(
        id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
        userId: json['user_id']?.toString() ?? '',
        actorId: json['actor_id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'unknown',
        postId: json['post_id'] != null 
            ? (json['post_id'] is int ? json['post_id'] : int.parse(json['post_id'].toString()))
            : null,
        commentId: json['comment_id'] != null
            ? (json['comment_id'] is int ? json['comment_id'] : int.parse(json['comment_id'].toString()))
            : null,
        message: json['message']?.toString() ?? '',
        isRead: json['is_read']?.toString().toLowerCase() == 'true' || json['is_read'] == true,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'].toString())
            : DateTime.now(),
        actorProfile: json['profiles'] is Map<String, dynamic> 
            ? Map<String, dynamic>.from(json['profiles'])
            : null,
      );
    } catch (e) {
      print('Error parsing notification from JSON: $e, json: $json');
      rethrow;
    }
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    
    if (difference.inMinutes < 1) return 'Только что';
    if (difference.inMinutes < 60) return '${difference.inMinutes} мин назад';
    if (difference.inHours < 24) return '${difference.inHours} ч назад';
    if (difference.inDays < 7) return '${difference.inDays} дн назад';
    return '${difference.inDays ~/ 7} нед назад';
  }

  IconData get icon {
    switch (type) {
      case 'follow':
        return Icons.person_add;
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.comment;
      default:
        return Icons.notifications;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'follow':
        return Colors.blueAccent;
      case 'like':
        return Colors.redAccent;
      case 'comment':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }
}