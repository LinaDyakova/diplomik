import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'package:timeago/timeago.dart' as timeago;

class ChatScreen extends StatefulWidget {
  final int chatId;
  final VoidCallback onMessagesRead;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.onMessagesRead,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _chatInfo;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isScreenActive = true;
  int _subscriberCount = 0;   
  int _participantCount = 0;  

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChatData();
    timeago.setLocaleMessages('ru', timeago.RuMessages());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isScreenActive) {
      _loadChatData();
    }
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _loadChatData();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadChatData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadChatData() async {
    try {
      setState(() => _isLoading = true);

      final chatResponse = await SupabaseConfig.client
          .rpc('get_chat_details', params: {'p_chat_id': widget.chatId})
          .single();

      final messagesResponse = await SupabaseConfig.client
          .rpc('get_chat_messages', params: {'p_chat_id': widget.chatId});

      List<Map<String, dynamic>> messages = [];
      if (messagesResponse != null) {
        if (messagesResponse is List) {
          messages = List<Map<String, dynamic>>.from(messagesResponse);
        } else if (messagesResponse is String) {
          try {
            final parsed = jsonDecode(messagesResponse);
            if (parsed is List) {
              messages = List<Map<String, dynamic>>.from(parsed);
            }
          } catch (e) {
            print('❌ Ошибка парсинга JSON: $e');
          }
        }
      }

      await _markMessagesAsRead();

      setState(() {
        _chatInfo = chatResponse;
        _messages = messages;
      });

      final chatType = _chatInfo?['type'] ?? (_chatInfo?['is_group'] == true ? 'group' : 'private');
      if (chatType == 'channel') {
        final countRes = await SupabaseConfig.client
            .from('chat_participants')
            .select('user_id')
            .eq('chat_id', widget.chatId);
        setState(() {
          _subscriberCount = countRes.length;
        });
      } else if (chatType == 'group') {
        final participants = _chatInfo?['chat_participants'] as List? ?? [];
        setState(() {
          _participantCount = participants.length;
        });
      }

      setState(() => _isLoading = false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      print('❌ Ошибка загрузки чата: $e');
      await _loadChatDataFallback();
    }
  }

  Future<void> _loadChatDataFallback() async {
    try {
      final messagesResponse = await SupabaseConfig.client
          .from('messages')
          .select('''
            *,
            profiles!messages_sender_id_fkey(username, avatar_url)
          ''')
          .eq('chat_id', widget.chatId)
          .order('created_at', ascending: true);

      final chatResponse = await SupabaseConfig.client
          .from('chats')
          .select('*')
          .eq('id', widget.chatId)
          .single();

      final participantsResponse = await SupabaseConfig.client
          .from('chat_participants')
          .select('''
            user_id,
            profiles!chat_participants_user_id_fkey(username, avatar_url)
          ''')
          .eq('chat_id', widget.chatId);

      await _markMessagesAsRead();

      setState(() {
        _chatInfo = {
          ...chatResponse,
          'chat_participants': participantsResponse
        };
        _messages = List<Map<String, dynamic>>.from(messagesResponse);
      });

      final chatType = _chatInfo?['type'] ?? (_chatInfo?['is_group'] == true ? 'group' : 'private');
      if (chatType == 'channel') {
        final countRes = await SupabaseConfig.client
            .from('chat_participants')
            .select('user_id')
            .eq('chat_id', widget.chatId);
        setState(() {
          _subscriberCount = countRes.length;
        });
      } else if (chatType == 'group') {
        final participants = _chatInfo?['chat_participants'] as List? ?? [];
        setState(() {
          _participantCount = participants.length;
        });
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('❌ Ошибка в fallback загрузке: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markMessagesAsRead() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await SupabaseConfig.client
          .from('messages')
          .update({'is_read': true})
          .eq('chat_id', widget.chatId)
          .neq('sender_id', userId)
          .eq('is_read', false);

      await SupabaseConfig.client
          .from('chat_participants')
          .update({'unread_count': 0})
          .eq('chat_id', widget.chatId)
          .eq('user_id', userId);

      widget.onMessagesRead();
    } catch (e) {
      print('❌ Ошибка пометки сообщений как прочитанных: $e');
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (message.isEmpty || userId == null) return;

    final chatType = _chatInfo?['type'] ?? (_chatInfo?['is_group'] == true ? 'group' : 'private');
    final creatorId = _chatInfo?['creator_id'];

    if (chatType == 'channel' && creatorId != userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Только создатель канала может отправлять сообщения')),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final response = await SupabaseConfig.client
          .rpc('send_chat_message', params: {
            'p_chat_id': widget.chatId,
            'p_sender_id': userId,
            'p_content': message,
          });

      Map<String, dynamic> messageData;
      if (response is Map<String, dynamic>) {
        messageData = response;
      } else if (response is String) {
        try {
          messageData = jsonDecode(response) as Map<String, dynamic>;
        } catch (e) {
          print('❌ Ошибка парсинга ответа: $e');
          messageData = {
            'id': DateTime.now().millisecondsSinceEpoch,
            'content': message,
            'sender_id': userId,
            'created_at': DateTime.now().toIso8601String(),
            'profiles': {'username': 'Вы', 'avatar_url': null}
          };
        }
      } else {
        throw Exception('Неизвестный формат ответа');
      }

      _messageController.clear();

      final messageExists = _messages.any((msg) =>
          msg['id'] == messageData['id'] ||
          (msg['content'] == message &&
              msg['sender_id'] == userId &&
              DateTime.parse(msg['created_at']).difference(DateTime.now()).inSeconds.abs() < 5));

      if (!messageExists) {
        setState(() {
          _messages.add(messageData);
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

      widget.onMessagesRead();
    } catch (e) {
      print('❌ Ошибка отправки сообщения: $e');
      await _sendMessageFallback(message, userId);
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _sendMessageFallback(String message, String userId) async {
    try {
      final newMessage = {
        'chat_id': widget.chatId,
        'sender_id': userId,
        'content': message,
        'message_type': 'text',
        'is_read': false,
      };
      await SupabaseConfig.client
          .from('messages')
          .insert(newMessage);

      await SupabaseConfig.client
          .from('chats')
          .update({
            'last_message': message,
            'last_message_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.chatId);

      final currentUnreadResponse = await SupabaseConfig.client
          .from('chat_participants')
          .select('unread_count')
          .eq('chat_id', widget.chatId)
          .neq('user_id', userId)
          .maybeSingle();
      int currentUnread = 0;
      if (currentUnreadResponse != null && currentUnreadResponse['unread_count'] != null) {
        currentUnread = currentUnreadResponse['unread_count'] as int;
      }
      await SupabaseConfig.client
          .from('chat_participants')
          .update({'unread_count': currentUnread + 1})
          .eq('chat_id', widget.chatId)
          .neq('user_id', userId);

      _messageController.clear();
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadChatData();
    } catch (e) {
      print('❌ Ошибка в fallback отправке: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка отправки: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getChatName() {
    final userId = SupabaseConfig.auth.currentUser?.id ?? '';
    if (_chatInfo == null) return 'Чат';
    final type = _chatInfo!['type'] ?? (_chatInfo!['is_group'] == true ? 'group' : 'private');
    if (type == 'channel') {
      return _chatInfo!['group_name'] ?? 'Канал';
    } else if (type == 'group') {
      return _chatInfo!['group_name'] ?? 'Групповой чат';
    } else {
      final participants = _chatInfo!['chat_participants'] ?? [];
      for (var p in participants) {
        if (p['user_id'] != userId && p['profiles'] != null) {
          return '@${p['profiles']['username'] ?? 'Пользователь'}';
        }
      }
      return 'Чат';
    }
  }

  Future<void> _leaveOrDeleteChat() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    final type = _chatInfo?['type'] ?? (_chatInfo?['is_group'] == true ? 'group' : 'private');
    final isCreator = _chatInfo?['creator_id'] == userId;

    String confirmMessage;
    String actionButtonText;
    bool willDelete = false;

    if (type == 'channel') {
      if (isCreator) {
        confirmMessage = 'Удалить канал "${_chatInfo?['group_name']}"?';
        actionButtonText = 'Удалить';
        willDelete = true;
      } else {
        confirmMessage = 'Отписаться от канала "${_chatInfo?['group_name']}"?';
        actionButtonText = 'Отписаться';
      }
    } else if (type == 'group') {
      confirmMessage = 'Выйти из беседы "${_chatInfo?['group_name']}"?';
      actionButtonText = 'Выйти';
    } else {
      confirmMessage = 'Удалить чат?';
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
          'p_chat_id': widget.chatId,
          'p_user_id': userId,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Канал удалён'), backgroundColor: Colors.green),
        );
      } else {
        await SupabaseConfig.client.rpc('leave_chat', params: {
          'p_chat_id': widget.chatId,
          'p_user_id': userId,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(type == 'channel' ? 'Вы отписались от канала' : 'Вы вышли из чата'),
            backgroundColor: Colors.green,
          ),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _subscribeToChannel() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    final creatorId = _chatInfo?['creator_id'];
    if (creatorId == userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы создатель этого канала'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      await SupabaseConfig.client.rpc('subscribe_to_channel', params: {
        'p_chat_id': widget.chatId,
        'p_user_id': userId,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы подписались на канал'), backgroundColor: Colors.green),
      );
      _loadChatData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  bool _isUserParticipant() {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return false;
    final participants = _chatInfo?['chat_participants'] as List? ?? [];
    return participants.any((p) => p['user_id'] == userId);
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isOwnMessage) {
    final createdAt = message['created_at'] is String
        ? DateTime.parse(message['created_at'])
        : DateTime.now();
    final content = message['content']?.toString() ?? '';
    final profile = message['profiles'] ?? {};

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isOwnMessage
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOwnMessage)
            CircleAvatar(
              radius: 16,
              backgroundImage: profile['avatar_url'] != null
                  ? NetworkImage(profile['avatar_url'])
                  : null,
              child: profile['avatar_url'] == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
          if (!isOwnMessage) const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: isOwnMessage
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isOwnMessage && profile['username'] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: Text(
                      '@${profile['username']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isOwnMessage
                        ? Colors.blueAccent
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    content,
                    style: TextStyle(
                      color: isOwnMessage ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.only(
                    right: isOwnMessage ? 8 : 0,
                    left: isOwnMessage ? 0 : 8,
                  ),
                  child: Text(
                    timeago.format(createdAt, locale: 'ru'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    final userId = SupabaseConfig.auth.currentUser?.id;
    final chatType = _chatInfo?['type'] ?? (_chatInfo?['is_group'] == true ? 'group' : 'private');
    final creatorId = _chatInfo?['creator_id'];
    bool canWrite = true;

    if (chatType == 'channel') {
      canWrite = creatorId == userId;
    }

    if (!_isUserParticipant()) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Center(
          child: ElevatedButton(
            onPressed: _subscribeToChannel,
            child: const Text('Подписаться на канал'),
          ),
        ),
      );
    }

    if (!canWrite) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: const Center(
          child: Text(
            'Вы не можете писать в этом канале',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение...',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.blueAccent,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _isSending ? null : _sendMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddParticipantsDialog() async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) return;

    final followingRes = await SupabaseConfig.client
        .from('follows')
        .select('following_id')
        .eq('follower_id', currentUserId);
    final followingIds = followingRes.map((f) => f['following_id'] as String).toList();

    final followersRes = await SupabaseConfig.client
        .from('follows')
        .select('follower_id')
        .eq('following_id', currentUserId);
    final followerIds = followersRes.map((f) => f['follower_id'] as String).toList();

    final friendIds = followingIds.toSet().intersection(followerIds.toSet()).toList();

    if (friendIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У вас пока нет друзей')),
      );
      return;
    }

    final profiles = await SupabaseConfig.client
        .from('profiles')
        .select('id, username, avatar_url')
        .inFilter('id', friendIds);

    List<String> selectedUserIds = [];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Добавить участников'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: profiles.length,
                itemBuilder: (context, index) {
                  final user = profiles[index];
                  final isSelected = selectedUserIds.contains(user['id']);
                  return CheckboxListTile(
                    title: Text('@${user['username']}'),
                    value: isSelected,
                    onChanged: (selected) {
                      setStateDialog(() {
                        if (selected == true) {
                          selectedUserIds.add(user['id']);
                        } else {
                          selectedUserIds.remove(user['id']);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedUserIds.isEmpty) {
                    Navigator.pop(context);
                    return;
                  }
                  try {
                    await SupabaseConfig.client.rpc('add_chat_participants', params: {
                      'p_chat_id': widget.chatId,
                      'p_user_ids': selectedUserIds,
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Участники добавлены')),
                    );
                    Navigator.pop(context);
                    _loadChatData();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
                    );
                  }
                },
                child: const Text('Добавить'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatType = _chatInfo?['type'] ?? (_chatInfo?['is_group'] == true ? 'group' : 'private');
    final isChannel = chatType == 'channel';
    final isGroup = chatType == 'group';
    final isCreator = _chatInfo?['creator_id'] == SupabaseConfig.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isChannel) const Icon(Icons.mic, size: 20, color: Colors.black87),
                if (isGroup) const Icon(Icons.group, size: 20, color: Colors.black87),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getChatName(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (isChannel)
              Text(
                'Подписчиков: $_subscriberCount',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            if (isGroup)
              Text(
                'Участников: $_participantCount',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        actions: [
          if (isGroup)
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.blueAccent),
              onPressed: _showAddParticipantsDialog,
              tooltip: 'Добавить участников',
            ),
          IconButton(
            icon: Icon(
              isChannel
                  ? (isCreator ? Icons.delete_forever : Icons.exit_to_app)
                  : Icons.logout,
              color: Colors.red,
            ),
            onPressed: _leaveOrDeleteChat,
            tooltip: isChannel
                ? (isCreator ? 'Удалить канал' : 'Отписаться')
                : (isGroup ? 'Выйти из беседы' : 'Удалить чат'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Colors.blueAccent,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Загрузка сообщений...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
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
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Начните диалог первым',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadChatData,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final isOwnMessage = message['sender_id'] == SupabaseConfig.auth.currentUser?.id;
                              return _buildMessageBubble(message, isOwnMessage);
                            },
                          ),
                        ),
                ),
                _buildMessageInput(),
              ],
            ),
    );
  }
}