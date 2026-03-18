// screens/chat/chats_list_screen.dart
import 'package:flutter/material.dart';
import 'package:vroom/screens/chat/chat_screen.dart';
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
    // Используем функцию get_chats_with_profiles
    final response = await SupabaseConfig.client
        .rpc('get_chats_with_profiles', params: {'p_user_id': userId});

    if (response != null && response is List) {
      List<Map<String, dynamic>> chats = [];
      
      for (var chatData in response) {
        // Преобразуем динамические данные в Map
        final chatMap = Map<String, dynamic>.from(chatData);
        
        chats.add({
          'id': chatMap['chat_id'],
          'created_at': chatMap['created_at'],
          'updated_at': chatMap['updated_at'],
          'last_message': chatMap['last_message'],
          'last_message_at': chatMap['last_message_at'],
          'is_group': chatMap['is_group'] ?? false,
          'group_name': chatMap['group_name'],
          'group_photo_url': chatMap['group_photo_url'],
          'unread_count': chatMap['unread_count'] ?? 0,
          // Добавляем данные другого пользователя для негрупповых чатов
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
    // Простой запрос без сложных join
    // 1. Получаем список chat_id для пользователя
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

    // 2. Получаем информацию о чатах
    for (var chatId in chatIds) {
      try {
        // Получаем основную информацию о чате
        final chatResponse = await SupabaseConfig.client
            .from('chats')
            .select()
            .eq('id', chatId)
            .single();

        // Получаем участников этого чата
        final participantsData = await SupabaseConfig.client
            .from('chat_participants')
            .select('''
              user_id,
              unread_count,
              joined_at,
              profiles!chat_participants_user_id_fkey(username, avatar_url)
            ''')
            .eq('chat_id', chatId);

        // Форматируем участников
        final participants = (participantsData as List)
            .map((p) => {
                  'user_id': p['user_id'],
                  'username': p['profiles']?['username'] ?? 'Пользователь',
                  'avatar_url': p['profiles']?['avatar_url'],
                  'joined_at': p['joined_at'],
                  'unread_count': p['unread_count'] ?? 0,
                })
            .toList();

        // Получаем последнее сообщение
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

        // Находим unread_count для текущего пользователя
        final userParticipant = participantsResponse.firstWhere(
          (p) => p['chat_id'] == chatId,
          orElse: () => {'unread_count': 0},
        );

        chats.add({
          'id': chatId,
          'created_at': chatResponse['created_at'],
          'updated_at': chatResponse['updated_at'],
          'last_message': lastMessage,
          'last_message_at': lastMessageAt?.toIso8601String(),
          'is_group': chatResponse['is_group'] ?? false,
          'group_name': chatResponse['group_name'],
          'group_photo_url': chatResponse['group_photo_url'],
          'participants': participants,
          'unread_count': userParticipant['unread_count'] ?? 0,
        });
      } catch (e) {
        print('Ошибка загрузки чата $chatId: $e');
      }
    }

    // Сортируем по updated_at
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

  Future<void> _loadChatsFallback(String userId) async {
  try {
    // Получаем все чаты пользователя
    final chatsResponse = await SupabaseConfig.client
        .from('chats')
        .select('''
            *,
            chat_participants!inner(
              user_id,
              profiles!inner(username, avatar_url)
            )
          ''')
        .order('updated_at', ascending: false);

    List<Map<String, dynamic>> chats = [];

    for (var chat in chatsResponse) {
      // Получаем последнее сообщение
      final lastMessageResponse = await SupabaseConfig.client
          .from('messages')
          .select('content, created_at')
          .eq('chat_id', chat['id'])
          .order('created_at', ascending: false)
          .limit(1);

      final lastMessage = lastMessageResponse.isNotEmpty 
          ? lastMessageResponse[0]['content']
          : null;
      
      final lastMessageAt = lastMessageResponse.isNotEmpty 
          ? DateTime.parse(lastMessageResponse[0]['created_at'])
          : null;

      // Форматируем участников
      final participants = (chat['chat_participants'] as List)
          .where((p) => p['user_id'] != userId) // Исключаем текущего пользователя
          .map((p) => {
                'user_id': p['user_id'],
                'username': p['profiles']?['username'] ?? 'Пользователь',
                'avatar_url': p['profiles']?['avatar_url'],
                'joined_at': DateTime.now().toIso8601String(),
                'unread_count': 0,
              })
          .toList();

      // Получаем количество непрочитанных
      final unreadResponse = await SupabaseConfig.client
          .from('chat_participants')
          .select('unread_count')
          .eq('chat_id', chat['id'])
          .eq('user_id', userId)
          .single();

      chats.add({
        'id': chat['id'],
        'created_at': chat['created_at'],
        'updated_at': chat['updated_at'],
        'last_message': lastMessage,
        'last_message_at': lastMessageAt?.toIso8601String(),
        'is_group': chat['is_group'] ?? false,
        'group_name': chat['group_name'],
        'group_photo_url': chat['group_photo_url'],
        'participants': participants,
        'unread_count': unreadResponse['unread_count'] ?? 0,
      });
    }

    setState(() {
      _chats = chats;
      _isLoading = false;
    });
  } catch (e) {
    print('Ошибка fallback загрузки чатов: $e');
    setState(() => _isLoading = false);
  }
}

  Future<void> _loadUnreadCount() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      print('User not authenticated for notifications count');
      return;
    }

    try {
      print('Loading unread notifications count for user: $userId');
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
    // Покажем диалог поиска пользователей для начала чата
    await showDialog(
      context: context,
      builder: (context) => NewChatDialog(
        onChatCreated: (chatData) {
          _addChatToLocalList(chatData);
          _openChat(chatData['id']);
        },
      ),
    );
  }

  void _addChatToLocalList(Map<String, dynamic> chatData) {
    // Преобразуем данные чата в нужный формат
    final formattedChat = {
      'id': chatData['id'],
      'created_at': chatData['created_at'],
      'updated_at': chatData['updated_at'],
      'last_message': null,
      'last_message_at': null,
      'is_group': chatData['is_group'] ?? false,
      'group_name': chatData['group_name'],
      'group_photo_url': chatData['group_photo_url'],
      'participants': chatData['participants'],
      'unread_count': 0,
    };

    setState(() {
      // Добавляем чат в начало списка
      _chats.insert(0, formattedChat);
    });
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
      // После возвращения из чата обновляем список
      _loadChats();
      _loadUnreadCount();
    });
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
                      return _buildChatItem(chat);
                    },
                  ),
                ),
    );
  }

Widget _buildChatItem(Map<String, dynamic> chat) {
  final isGroup = chat['is_group'] ?? false;
  final unreadCount = chat['unread_count'] ?? 0;
  final lastMessage = chat['last_message'];
  final lastMessageAt = chat['last_message_at'] != null
      ? DateTime.parse(chat['last_message_at'].toString())
      : null;
  
  String chatName = 'Чат';
  String? avatarUrl;
  
  if (isGroup) {
    chatName = chat['group_name'] ?? 'Групповой чат';
    avatarUrl = chat['group_photo_url'];
  } else {
    // Используем напрямую поля из ответа функции
    chatName = '@${chat['other_username'] ?? 'Пользователь'}';
    avatarUrl = chat['other_avatar_url'];
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
                    isGroup ? Icons.group : Icons.person,
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

// Диалог для начала нового чата
class NewChatDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onChatCreated;

  const NewChatDialog({super.key, required this.onChatCreated});

  @override
  State<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<NewChatDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _searchResults.clear();
      });
      return;
    }

    _performSearch(_searchController.text.trim());
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    setState(() => _isSearching = true);

    try {
      final response = await SupabaseConfig.client
          .from('profiles')
          .select('id, username, avatar_url, bio')
          .ilike('username', '%$query%')
          .neq('id', SupabaseConfig.auth.currentUser!.id) // Исключаем себя
          .limit(10);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(response);
        _isSearching = false;
      });
    } catch (e) {
      print('Ошибка поиска пользователей: $e');
      setState(() => _isSearching = false);
    }
  }

  Future<void> _createPrivateChat(Map<String, dynamic> user) async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // Используем функцию для создания приватного чата
      final response = await SupabaseConfig.client
          .rpc('create_private_chat', params: {
            'user1_id': currentUserId,
            'user2_id': user['id'],
          });

      if (response != null) {
        if (response is Map<String, dynamic>) {
          // Если функция возвращает полные данные о чате
          widget.onChatCreated(response);
        } else {
          // Если функция возвращает только ID
          final chatId = response as int;
          
          // Загружаем данные о чате вручную
          final chatResponse = await SupabaseConfig.client
              .from('chats')
              .select('''
                *,
                chat_participants!inner(
                  user_id,
                  profiles!inner(username, avatar_url)
                )
              ''')
              .eq('id', chatId)
              .single();

          // Форматируем данные чата
          final participants = (chatResponse['chat_participants'] as List)
              .where((p) => p['user_id'] != currentUserId)
              .map((p) => {
                    'user_id': p['user_id'],
                    'username': p['profiles']?['username'] ?? 'Пользователь',
                    'avatar_url': p['profiles']?['avatar_url'],
                    'joined_at': DateTime.now().toIso8601String(),
                    'unread_count': 0,
                  })
              .toList();

          final chatData = {
            'id': chatId,
            'created_at': chatResponse['created_at'],
            'updated_at': chatResponse['updated_at'],
            'is_group': chatResponse['is_group'] ?? false,
            'group_name': chatResponse['group_name'],
            'group_photo_url': chatResponse['group_photo_url'],
            'participants': participants,
          };

          widget.onChatCreated(chatData);
        }
      }
    } catch (e) {
      print('Ошибка создания чата: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка создания чата: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500,
          maxHeight: 600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Новый диалог',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Поиск пользователей...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    autofocus: true,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.blueAccent,
                      ),
                    )
                  : _searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _searchController.text.isEmpty
                                    ? Icons.search
                                    : Icons.search_off,
                                size: 60,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                    ? 'Начните вводить имя пользователя'
                                    : 'Пользователи не найдены',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final user = _searchResults[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.grey[200],
                                  backgroundImage: user['avatar_url'] != null
                                      ? NetworkImage(user['avatar_url'])
                                      : null,
                                  child: user['avatar_url'] == null
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.grey,
                                        )
                                      : null,
                                ),
                                title: Text(
                                  '@${user['username']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: user['bio'] != null
                                    ? Text(
                                        user['bio'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      )
                                    : null,
                                trailing: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.message,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                onTap: () => _createPrivateChat(user),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}