import 'package:flutter/material.dart';
import 'package:vroom/screens/chat/chat_screen.dart';
import 'package:vroom/screens/chat/create_group_chat_screen.dart';
import 'package:vroom/screens/search/search_screen.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'package:timeago/timeago.dart' as timeago;

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadChats();
    _loadUnreadCount();
    timeago.setLocaleMessages('ru', timeago.RuMessages());
  }

  Future<void> _loadChats() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await SupabaseConfig.client
          .rpc('get_chats_with_profiles', params: {'p_user_id': userId});

      if (response != null && response is List) {
        List<Map<String, dynamic>> chats = [];

        for (var chatData in response) {
          final chatMap = Map<String, dynamic>.from(chatData);

          chats.add({
            'id': chatMap['chat_id'],
            'created_at': chatMap['created_at'],
            'updated_at': chatMap['updated_at'],
            'last_message': chatMap['last_message'],
            'last_message_at': chatMap['last_message_at'],
            'is_group': chatMap['is_group'] ?? false,
            'type': chatMap['type'] ?? (chatMap['is_group'] == true ? 'group' : 'private'),
            'group_name': chatMap['group_name'],
            'group_photo_url': chatMap['group_photo_url'],
            'unread_count': chatMap['unread_count'] ?? 0,
            'creator_id': chatMap['creator_id'],
            'other_user_id': chatMap['other_user_id'],
            'other_username': chatMap['other_username'],
            'other_avatar_url': chatMap['other_avatar_url'],
          });
        }

        setState(() {
          _chats = chats;
          _isLoading = false;
        });
        print('Загружено ${_chats.length} чатов');
      } else {
        await _loadChatsSimple(userId);
      }
    } catch (e) {
      print('Ошибка загрузки чатов: $e');
      await _loadChatsSimple(userId);
    }
  }

  Future<void> _loadChatsSimple(String userId) async {
    try {
      final participantsResponse = await SupabaseConfig.client
          .from('chat_participants')
          .select('chat_id, unread_count')
          .eq('user_id', userId);

      if (participantsResponse.isEmpty) {
        setState(() {
          _chats = [];
          _isLoading = false;
        });
        return;
      }

      List<Map<String, dynamic>> chats = [];
      final chatIds = participantsResponse.map((p) => p['chat_id'] as int).toList();

      for (var chatId in chatIds) {
        try {
          final chatResponse = await SupabaseConfig.client
              .from('chats')
              .select()
              .eq('id', chatId)
              .single();

          final participantsData = await SupabaseConfig.client
              .from('chat_participants')
              .select('''
                user_id,
                unread_count,
                joined_at,
                profiles!chat_participants_user_id_fkey(username, avatar_url)
              ''')
              .eq('chat_id', chatId);

          final participants = (participantsData as List)
              .map((p) => {
                    'user_id': p['user_id'],
                    'username': p['profiles']?['username'] ?? 'Пользователь',
                    'avatar_url': p['profiles']?['avatar_url'],
                    'joined_at': p['joined_at'],
                    'unread_count': p['unread_count'] ?? 0,
                  })
              .toList();

          final lastMessageResponse = await SupabaseConfig.client
              .from('messages')
              .select('content, created_at')
              .eq('chat_id', chatId)
              .order('created_at', ascending: false)
              .limit(1);

          final lastMessage = lastMessageResponse.isNotEmpty
              ? lastMessageResponse[0]['content']
              : null;
          final lastMessageAt = lastMessageResponse.isNotEmpty
              ? DateTime.parse(lastMessageResponse[0]['created_at'])
              : null;

          final userParticipant = participantsResponse.firstWhere(
            (p) => p['chat_id'] == chatId,
            orElse: () => {'unread_count': 0},
          );

          final isGroup = chatResponse['is_group'] ?? false;
          final type = chatResponse['type'] ?? (isGroup ? 'group' : 'private');

          chats.add({
            'id': chatId,
            'created_at': chatResponse['created_at'],
            'updated_at': chatResponse['updated_at'],
            'last_message': lastMessage,
            'last_message_at': lastMessageAt?.toIso8601String(),
            'is_group': isGroup,
            'type': type,
            'group_name': chatResponse['group_name'],
            'group_photo_url': chatResponse['group_photo_url'],
            'participants': participants,
            'unread_count': userParticipant['unread_count'] ?? 0,
            'creator_id': chatResponse['creator_id'],
          });
        } catch (e) {
          print('Ошибка загрузки чата $chatId: $e');
        }
      }

      chats.sort((a, b) {
        final dateA = DateTime.parse(b['updated_at']);
        final dateB = DateTime.parse(a['updated_at']);
        return dateA.compareTo(dateB);
      });

      setState(() {
        _chats = chats;
        _isLoading = false;
      });
      print('Загружено ${chats.length} чатов через simple метод');
    } catch (e) {
      print('Ошибка simple загрузки чатов: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUnreadCount() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await SupabaseConfig.client
          .rpc('get_unread_messages_count', params: {'user_uuid': userId});
      if (response != null) {
        setState(() {
          _unreadCount = response as int;
        });
      }
    } catch (e) {
      print('Error loading unread notifications count: $e');
    }
  }

  Future<void> _startNewChat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateGroupChatScreen()),
    );
    if (result == true) {
      _loadChats();
      _loadUnreadCount();
    }
  }

  void _openChat(int chatId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: chatId,
          onMessagesRead: () {
            _loadChats();
            _loadUnreadCount();
          },
        ),
      ),
    ).then((_) {
      _loadChats();
      _loadUnreadCount();
    });
  }

  Future<void> _leaveOrDeleteChat(Map<String, dynamic> chat) async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    final type = chat['type'] ?? (chat['is_group'] ? 'group' : 'private');
    final isCreator = chat['creator_id'] == userId;
    final isChannel = type == 'channel';
    final isGroup = type == 'group';

    String confirmMessage;
    String actionButtonText;
    bool willDelete = false;

    if (isChannel) {
      if (isCreator) {
        confirmMessage = 'Удалить канал "${chat['group_name']}"?';
        actionButtonText = 'Удалить';
        willDelete = true;
      } else {
        confirmMessage = 'Отписаться от канала "${chat['group_name']}"?';
        actionButtonText = 'Отписаться';
      }
    } else if (isGroup) {
      confirmMessage = 'Выйти из беседы "${chat['group_name']}"?';
      actionButtonText = 'Выйти';
    } else {
      confirmMessage = 'Удалить чат с ${chat['other_username']}?';
      actionButtonText = 'Удалить';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(confirmMessage),
        content: const Text('Все сообщения останутся у других участников.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(actionButtonText),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (willDelete) {
        await SupabaseConfig.client.rpc('delete_chat', params: {
          'p_chat_id': chat['id'],
          'p_user_id': userId,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Канал удалён'), backgroundColor: Colors.green),
        );
      } else {
        await SupabaseConfig.client.rpc('leave_chat', params: {
          'p_chat_id': chat['id'],
          'p_user_id': userId,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isChannel ? 'Вы отписались от канала' : 'Вы вышли из чата'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadChats(); 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 20),
          const Text(
            'Нет сообщений',
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
              'Начните общение с другими пользователями',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _startNewChat,
            icon: const Icon(Icons.add_comment),
            label: const Text('Начать диалог'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
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
          'Сообщения',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.blueAccent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SearchScreen()),
            ),
          ),
          IconButton(
            onPressed: _startNewChat,
            icon: const Icon(Icons.edit, color: Colors.blueAccent),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.blueAccent,
              ),
            )
          : _chats.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadChats();
                    await _loadUnreadCount();
                  },
                  backgroundColor: Colors.white,
                  color: Colors.blueAccent,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _chats.length,
                    itemBuilder: (context, index) {
                      final chat = _chats[index];
                      return Dismissible(
                        key: Key(chat['id'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Удалить чат?'),
                              content: const Text('Вы выйдете из чата. Это действие нельзя отменить.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Отмена'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('Удалить'),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) {
                          _leaveOrDeleteChat(chat);
                        },
                        child: _buildChatItem(chat),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildChatItem(Map<String, dynamic> chat) {
    final isGroup = chat['is_group'] ?? false;
    final type = chat['type'] ?? (isGroup ? 'group' : 'private');
    final unreadCount = chat['unread_count'] ?? 0;
    final lastMessage = chat['last_message'];
    final lastMessageAt = chat['last_message_at'] != null
        ? DateTime.parse(chat['last_message_at'].toString())
        : null;

    String chatName = 'Чат';
    String? avatarUrl;
    IconData? leadingIcon;

    if (type == 'channel') {
      chatName = chat['group_name'] ?? 'Канал';
      avatarUrl = chat['group_photo_url'];
      leadingIcon = Icons.mic;
    } else if (type == 'group') {
      chatName = chat['group_name'] ?? 'Групповой чат';
      avatarUrl = chat['group_photo_url'];
      leadingIcon = Icons.group;
    } else {
      chatName = '@${chat['other_username'] ?? 'Пользователь'}';
      avatarUrl = chat['other_avatar_url'];
      leadingIcon = Icons.person;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.grey[200],
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Icon(
                      leadingIcon ?? (isGroup ? Icons.group : Icons.person),
                      color: Colors.grey,
                      size: 28,
                    )
                  : null,
            ),
            if (unreadCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          chatName,
          style: TextStyle(
            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
            fontSize: 16,
          ),
        ),
        subtitle: lastMessage != null
            ? Text(
                lastMessage.toString().length > 40
                    ? '${lastMessage.toString().substring(0, 40)}...'
                    : lastMessage.toString(),
                style: TextStyle(
                  color: unreadCount > 0 ? Colors.black87 : Colors.grey[600],
                  fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : const Text('Начните диалог'),
        trailing: lastMessageAt != null
            ? Text(
                timeago.format(lastMessageAt, locale: 'ru'),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              )
            : null,
        onTap: () => _openChat(chat['id']),
      ),
    );
  }
}