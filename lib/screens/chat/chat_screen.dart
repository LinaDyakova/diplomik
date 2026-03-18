// screens/chat/chat_screen.dart
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

  @override
  void initState() {
    super.initState();
    print('Инициализация чата ${widget.chatId}');
    
    // Добавляем observer для отслеживания видимости экрана
    WidgetsBinding.instance.addObserver(this);
    
    _loadChatData();
    timeago.setLocaleMessages('ru', timeago.RuMessages());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Обновляем данные при каждом входе в чат
    if (_isScreenActive) {
      print('Экран стал активным, обновляю данные...');
      _loadChatData();
    }
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если chatId изменился, перезагружаем данные
    if (oldWidget.chatId != widget.chatId) {
      _loadChatData();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Отслеживаем переход приложения в активное состояние
    if (state == AppLifecycleState.resumed) {
      print('Приложение вернулось в активное состояние, обновляю чат...');
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
      print('=== НАЧАЛО ЗАГРУЗКИ ЧАТА ${widget.chatId} ===');
      setState(() => _isLoading = true);
      
      // 1. Загружаем информацию о чате
      print('1. Загружаю информацию о чате...');
      final chatResponse = await SupabaseConfig.client
          .rpc('get_chat_details', params: {'p_chat_id': widget.chatId})
          .single();
      print('✅ Информация о чате загружена');

      // 2. Загружаем сообщения
      print('2. Загружаю сообщения...');
      final messagesResponse = await SupabaseConfig.client
          .rpc('get_chat_messages', params: {'p_chat_id': widget.chatId});
      
      print('📊 Тип ответа messagesResponse: ${messagesResponse.runtimeType}');
      
      List<Map<String, dynamic>> messages = [];
      
      if (messagesResponse != null) {
        if (messagesResponse is List) {
          print('📋 Ответ является List, длина: ${messagesResponse.length}');
          messages = List<Map<String, dynamic>>.from(messagesResponse);
        } else if (messagesResponse is String) {
          print('📝 Ответ является String, парсим JSON');
          try {
            final parsed = jsonDecode(messagesResponse);
            if (parsed is List) {
              messages = List<Map<String, dynamic>>.from(parsed);
            }
          } catch (e) {
            print('❌ Ошибка парсинга JSON: $e');
          }
        } else {
          print('⚠️ Неизвестный тип ответа: ${messagesResponse.runtimeType}');
        }
      }

      // Помечаем сообщения как прочитанные
      await _markMessagesAsRead();

      setState(() {
        _chatInfo = chatResponse;
        _messages = messages;
        _isLoading = false;
      });

      print('✅ Загружено ${_messages.length} сообщений для чата ${widget.chatId}');
      
      // Прокручиваем к последнему сообщению
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
      print('🔄 Использую fallback метод загрузки чата');
      
      // Альтернативный способ загрузки сообщений
      final messagesResponse = await SupabaseConfig.client
          .from('messages')
          .select('''
            *,
            profiles!messages_sender_id_fkey(username, avatar_url)
          ''')
          .eq('chat_id', widget.chatId)
          .order('created_at', ascending: true);

      // Загружаем информацию о чате
      final chatResponse = await SupabaseConfig.client
          .from('chats')
          .select('*')
          .eq('id', widget.chatId)
          .single();

      // Получаем участников чата
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
        _isLoading = false;
      });
      
      print('✅ Fallback: Загружено ${_messages.length} сообщений');
    } catch (e) {
      print('❌ Ошибка в fallback загрузке: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markMessagesAsRead() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Помечаем сообщения других пользователей как прочитанные
      await SupabaseConfig.client
          .from('messages')
          .update({'is_read': true})
          .eq('chat_id', widget.chatId)
          .neq('sender_id', userId)
          .eq('is_read', false);

      // Сбрасываем счетчик непрочитанных
      await SupabaseConfig.client
          .from('chat_participants')
          .update({'unread_count': 0})
          .eq('chat_id', widget.chatId)
          .eq('user_id', userId);

      widget.onMessagesRead();
      print('✅ Сообщения помечены как прочитанные');
    } catch (e) {
      print('❌ Ошибка пометки сообщений как прочитанных: $e');
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    final userId = SupabaseConfig.auth.currentUser?.id;

    if (message.isEmpty || userId == null) return;

    setState(() => _isSending = true);

    try {
      print('📤 Отправляю сообщение: "$message" в чат ${widget.chatId}');
      
      final response = await SupabaseConfig.client
          .rpc('send_chat_message', params: {
            'p_chat_id': widget.chatId,
            'p_sender_id': userId,
            'p_content': message,
          });

      print('📩 Ответ от send_chat_message: $response');

      if (response != null) {
        // Преобразуем ответ в Map
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

        // Очищаем поле ввода
        _messageController.clear();

        // Проверяем, нет ли уже такого сообщения в списке
        final messageExists = _messages.any((msg) => 
            msg['id'] == messageData['id'] || 
            (msg['content'] == message && 
             msg['sender_id'] == userId && 
             DateTime.parse(msg['created_at']).difference(DateTime.now()).inSeconds.abs() < 5));
        
        if (!messageExists) {
          setState(() {
            _messages.add(messageData);
          });
          print('✅ Сообщение добавлено в локальный список');
        } else {
          print('⚠️ Сообщение уже существует в списке');
        }

        // Прокручиваем к последнему сообщению
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        // Обновляем счетчик непрочитанных
        widget.onMessagesRead();
      }
    } catch (e) {
      print('❌ Ошибка отправки сообщения: $e');
      await _sendMessageFallback(message, userId);
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _sendMessageFallback(String message, String userId) async {
    try {
      print('🔄 Использую fallback отправку сообщения');
      
      // Прямая вставка в таблицу messages
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

      // Обновляем last_message в чате вручную
      await SupabaseConfig.client
          .from('chats')
          .update({
            'last_message': message,
            'last_message_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.chatId);

      // Увеличиваем счетчик непрочитанных для других участников
      // Получаем текущее значение unread_count
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
      
      // Перезагружаем сообщения через короткую задержку
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

    final isGroup = _chatInfo!['is_group'] ?? false;
    if (isGroup) {
      return _chatInfo!['group_name'] ?? 'Групповой чат';
    }

    final participants = _chatInfo!['chat_participants'] ?? [];
    
    if (participants is List) {
      for (var p in participants) {
        if (p['user_id'] != userId && p['profiles'] != null) {
          return '@${p['profiles']['username'] ?? 'Пользователь'}';
        }
      }
    }

    return 'Чат';
  }

  @override
  Widget build(BuildContext context) {
    final userId = SupabaseConfig.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _getChatName(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            onPressed: _isLoading ? null : _loadChatData,
            tooltip: 'Обновить чат',
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
                              final isOwnMessage = message['sender_id'] == userId;
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
}