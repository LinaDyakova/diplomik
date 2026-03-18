import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:vroom/models/notification_model.dart';
import 'package:vroom/screens/profile/other_profile_screen.dart';
import 'package:vroom/screens/post/post_detail_screen.dart';
import 'package:vroom/supabase/supabase_config.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    // Инициализируем timeago с русской локалью
    timeago.setLocaleMessages('ru', timeago.RuMessages());
  }

  Future<void> _loadNotifications() async {
  try {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      print('Пользователь не авторизован');
      setState(() => _isLoading = false);
      return;
    }

    print('ID текущего пользователя: $userId');
    
    // Тестовый запрос - проверьте, что возвращает
    final testResponse = await SupabaseConfig.client
        .from('notifications')
        .select('*')
        .eq('user_id', userId);
    
    print('Тестовый запрос (без join): $testResponse');
    print('Количество уведомлений: ${testResponse.length}');

    // Основной запрос с join
    final response = await SupabaseConfig.client
        .from('notifications')
        .select('''
          *,
          profiles!notifications_actor_id_fkey(username, avatar_url)
        ''')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    print('Основной запрос: $response');
    
    if (response != null && response is List) {
      List<NotificationModel> notifications = [];
      
      for (var item in response) {
        try {
          print('Обрабатываю уведомление: $item');
          final notification = NotificationModel.fromJson(item);
          notifications.add(notification);
        } catch (e) {
          print('Ошибка парсинга: $e');
        }
      }

      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
      
      print('Загружено ${notifications.length} уведомлений');
    }
  } catch (e, stackTrace) {
    print('Ошибка загрузки уведомлений: $e');
    print('Stack trace: $stackTrace');
    setState(() => _isLoading = false);
  }
}

  Future<void> _markAsRead(NotificationModel notification) async {
    if (notification.isRead) return;

    try {
      await SupabaseConfig.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notification.id);

      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notification.id);
        if (index != -1) {
          _notifications[index] = NotificationModel(
            id: notification.id,
            userId: notification.userId,
            actorId: notification.actorId,
            type: notification.type,
            postId: notification.postId,
            commentId: notification.commentId,
            message: notification.message,
            isRead: true,
            createdAt: notification.createdAt,
            actorProfile: notification.actorProfile,
          );
          _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
        }
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await SupabaseConfig.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      // Обновляем локальный список
      for (var i = 0; i < _notifications.length; i++) {
        _notifications[i] = NotificationModel(
          id: _notifications[i].id,
          userId: _notifications[i].userId,
          actorId: _notifications[i].actorId,
          type: _notifications[i].type,
          postId: _notifications[i].postId,
          commentId: _notifications[i].commentId,
          message: _notifications[i].message,
          isRead: true,
          createdAt: _notifications[i].createdAt,
          actorProfile: _notifications[i].actorProfile,
        );
      }

      setState(() {
        _unreadCount = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Все уведомления прочитаны'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error marking all notifications as read: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleNotificationTap(NotificationModel notification) async {
    // Помечаем как прочитанное
    await _markAsRead(notification);

    // В зависимости от типа уведомления переходим на нужный экран
    switch (notification.type) {
      case 'follow':
        // Переходим в профиль того, кто подписался
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                OtherProfileScreen(userId: notification.actorId),
          ),
        );
        break;
      case 'like':
      case 'comment':
        // Переходим к посту
        if (notification.postId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  PostDetailScreen(postId: notification.postId!),
            ),
          );
        }
        break;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 20),
          const Text(
            'Нет уведомлений',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              'Здесь будут появляться уведомления о подписках, лайках и комментариях',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

// В классе _buildNotificationItem в notifications_screen.dart
// Измените RichText чтобы он не дублировал username:

Widget _buildNotificationItem(NotificationModel notification) {
  final actorProfile = notification.actorProfile;
  final actorUsername = actorProfile != null 
      ? (actorProfile['username']?.toString() ?? 'Пользователь')
      : 'Пользователь';
  final actorAvatar = actorProfile?['avatar_url']?.toString();

  return GestureDetector(
    onTap: () => _handleNotificationTap(notification),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Иконка типа уведомления
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: notification.iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                notification.icon,
                color: notification.iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            
            // Содержимое уведомления
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Текст уведомления с юзернеймом в начале
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: notification.isRead 
                            ? FontWeight.normal 
                            : FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: '@$actorUsername ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: notification.message),
                      ],
                    ),
                  ),
                  
                  // Время и аватар
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Аватар пользователя
                      if (actorAvatar != null && actorAvatar.isNotEmpty)
                        CircleAvatar(
                          radius: 12,
                          backgroundImage: NetworkImage(actorAvatar),
                        )
                      else
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.grey[200],
                          child: const Icon(
                            Icons.person,
                            size: 12,
                            color: Colors.grey,
                          ),
                        ),
                      
                      const SizedBox(width: 8),
                      
                      // Время
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        notification.timeAgo,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      
                      // Индикатор непрочитанного
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Уведомления',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Прочитать все'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blueAccent,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.blueAccent,
              ),
            )
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  backgroundColor: Colors.white,
                  color: Colors.blueAccent,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      return _buildNotificationItem(notification);
                    },
                  ),
                ),
    );
  }
}