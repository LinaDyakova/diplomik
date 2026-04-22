import 'package:flutter/material.dart';
import 'package:vroom/screens/chat/chat_screen.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'dart:async';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _userResults = [];
  List<Map<String, dynamic>> _channelResults = [];
  bool _isSearching = false;
  Timer? _debounce;
  String _lastQuery = '';
  Set<int> _subscribedChannelIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadSubscribedChannels();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final query = _searchController.text.trim();
      _lastQuery = query;
      _performSearch(query);
    });
  }

  Future<void> _loadSubscribedChannels() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await SupabaseConfig.client
          .from('chat_participants')
          .select('chat_id')
          .eq('user_id', userId);
      _subscribedChannelIds = response.map((r) => r['chat_id'] as int).toSet();
    } catch (e) {
      print('Error loading subscribed channels: $e');
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _userResults.clear();
        _channelResults.clear();
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final usersRes = await SupabaseConfig.client
          .from('profiles')
          .select('id, username, avatar_url')
          .ilike('username', '%$query%')
          .limit(10);
      setState(() {
        _userResults = List<Map<String, dynamic>>.from(usersRes);
      });

      final channelsRes = await SupabaseConfig.client
          .from('chats')
          .select('id, group_name, group_photo_url, creator_id')
          .eq('type', 'channel')
          .ilike('group_name', '%$query%')
          .limit(10);

      List<Map<String, dynamic>> channels = [];
      for (var ch in channelsRes) {
        final countRes = await SupabaseConfig.client
            .from('chat_participants')
            .select('user_id')
            .eq('chat_id', ch['id']);
        final subscriberCount = countRes.length;
        final isSubscribed = _subscribedChannelIds.contains(ch['id']);
        channels.add({
          ...ch,
          'subscriber_count': subscriberCount,
          'is_subscribed': isSubscribed,
        });
      }
      setState(() {
        _channelResults = channels;
        _isSearching = false;
      });
    } catch (e) {
      print('Search error: $e');
      setState(() => _isSearching = false);
    }
  }

  Future<void> _startPrivateChat(String userId, String username) async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) return;

    final isFollowing = await SupabaseConfig.client
        .from('follows')
        .select()
        .eq('follower_id', currentUserId)
        .eq('following_id', userId)
        .maybeSingle();
    final isFollowedBack = await SupabaseConfig.client
        .from('follows')
        .select()
        .eq('follower_id', userId)
        .eq('following_id', currentUserId)
        .maybeSingle();

    if (isFollowing == null || isFollowedBack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Вы можете писать только друзьям'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final response = await SupabaseConfig.client.rpc('create_private_chat', params: {
        'user1_id': currentUserId,
        'user2_id': userId,
      });
      if (response != null) {
        final chatId = response is int ? response : response['id'];
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: chatId,
              onMessagesRead: () {},
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleSubscription(Map<String, dynamic> channel) async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    if (channel['creator_id'] == userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы создатель этого канала'), backgroundColor: Colors.orange),
      );
      return;
    }

    final isSubscribed = channel['is_subscribed'];
    try {
      if (isSubscribed) {
        await SupabaseConfig.client.rpc('leave_chat', params: {
          'p_chat_id': channel['id'],
          'p_user_id': userId,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы отписались от канала'), backgroundColor: Colors.green),
        );
        setState(() {
          _subscribedChannelIds.remove(channel['id']);
          final index = _channelResults.indexWhere((c) => c['id'] == channel['id']);
          if (index != -1) {
            _channelResults[index]['is_subscribed'] = false;
            _channelResults[index]['subscriber_count']--;
          }
        });
      } else {
        await SupabaseConfig.client.rpc('subscribe_to_channel', params: {
          'p_chat_id': channel['id'],
          'p_user_id': userId,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы подписались на канал'), backgroundColor: Colors.green),
        );
        setState(() {
          _subscribedChannelIds.add(channel['id']);
          final index = _channelResults.indexWhere((c) => c['id'] == channel['id']);
          if (index != -1) {
            _channelResults[index]['is_subscribed'] = true;
            _channelResults[index]['subscriber_count']++;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text('Поиск', style: TextStyle(color: Colors.black87)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Введите имя пользователя или название канала',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          if (_isSearching)
            const Center(child: CircularProgressIndicator())
          else if (_searchController.text.isEmpty)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Начните поиск', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_userResults.isNotEmpty) ...[
                    const Text('Пользователи', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._userResults.map((user) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user['avatar_url'] != null
                              ? NetworkImage(user['avatar_url'])
                              : null,
                          child: user['avatar_url'] == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text('@${user['username']}'),
                        trailing: ElevatedButton(
                          onPressed: () => _startPrivateChat(user['id'], user['username']),
                          child: const Text('Написать'),
                        ),
                      ),
                    )),
                    const SizedBox(height: 16),
                  ],
                  if (_channelResults.isNotEmpty) ...[
                    const Text('Каналы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._channelResults.map((channel) {
                      final isCreator = channel['creator_id'] == SupabaseConfig.auth.currentUser?.id;
                      final isSubscribed = channel['is_subscribed'];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[200],
                            backgroundImage: channel['group_photo_url'] != null
                                ? NetworkImage(channel['group_photo_url'])
                                : null,
                            child: channel['group_photo_url'] == null
                                ? const Icon(Icons.mic, color: Colors.grey)
                                : null,
                          ),
                          title: Text(channel['group_name'] ?? 'Канал'),
                          subtitle: Text('Подписчиков: ${channel['subscriber_count']}'),
                          trailing: isCreator
                              ? const Text('Создатель', style: TextStyle(color: Colors.grey))
                              : ElevatedButton(
                                  onPressed: () => _toggleSubscription(channel),
                                  child: Text(isSubscribed ? 'Отписаться' : 'Подписаться'),
                                ),
                        ),
                      );
                    }),
                  ],
                  if (_userResults.isEmpty && _channelResults.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Ничего не найдено'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}