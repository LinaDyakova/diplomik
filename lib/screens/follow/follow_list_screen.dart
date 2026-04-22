import 'package:flutter/material.dart';
import 'package:vroom/screens/profile/other_profile_screen.dart';
import 'package:vroom/supabase/supabase_config.dart';

class FollowListScreen extends StatefulWidget {
  final String userId;
  final String type; 
  final String title;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.type,
    required this.title,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  Map<String, bool> _followingStatus = {}; 
  Map<String, bool> _friendshipStatus = {}; 

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      List<Map<String, dynamic>> users = [];

      if (widget.type == 'followers') {
        final response = await SupabaseConfig.client
            .from('follows')
            .select('follower_id')
            .eq('following_id', widget.userId);

        final followerIds = response.map((item) => item['follower_id'] as String).toList();

        if (followerIds.isNotEmpty) {
          final profilesResponse = await SupabaseConfig.client
              .from('profiles')
              .select('id, username, avatar_url, bio')
              .inFilter('id', followerIds);

          for (var profile in profilesResponse) {
            users.add({
              'id': profile['id'],
              'username': profile['username'],
              'avatar_url': profile['avatar_url'],
              'bio': profile['bio'],
            });
          }
        }
      } else if (widget.type == 'following') {
        final response = await SupabaseConfig.client
            .from('follows')
            .select('following_id')
            .eq('follower_id', widget.userId);

        final followingIds = response.map((item) => item['following_id'] as String).toList();

        if (followingIds.isNotEmpty) {
          final profilesResponse = await SupabaseConfig.client
              .from('profiles')
              .select('id, username, avatar_url, bio')
              .inFilter('id', followingIds);

          for (var profile in profilesResponse) {
            users.add({
              'id': profile['id'],
              'username': profile['username'],
              'avatar_url': profile['avatar_url'],
              'bio': profile['bio'],
            });
          }
        }
      }

      await _loadFollowingStatus(users);
      
      await _loadFriendshipStatus(users);

      setState(() {
        _users = users;
        _isLoading = false;
      });
      
      print('Загружено ${users.length} пользователей');
    } catch (e) {
      print('Error loading ${widget.type}: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFollowingStatus(List<Map<String, dynamic>> users) async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final userIds = users.map((user) => user['id'] as String).toList();
      
      if (userIds.isEmpty) return;

      final response = await SupabaseConfig.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', currentUserId)
          .inFilter('following_id', userIds);

      final followingSet = Set<String>.from(
        response.map((item) => item['following_id'] as String)
      );

      for (var user in users) {
        final userId = user['id'] as String;
        _followingStatus[userId] = followingSet.contains(userId);
      }
      
      print('Статусы подписки загружены для ${followingSet.length} пользователей');
    } catch (e) {
      print('Error checking follow status: $e');
    }
  }

  Future<void> _loadFriendshipStatus(List<Map<String, dynamic>> users) async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      for (var user in users) {
        final userId = user['id'] as String;
        
        if (currentUserId == userId) {
          _friendshipStatus[userId] = false;
          continue;
        }
        
        final isFollowingResponse = await SupabaseConfig.client
            .from('follows')
            .select()
            .eq('follower_id', currentUserId)
            .eq('following_id', userId);
        
        final isCurrentUserFollowing = isFollowingResponse.isNotEmpty;
        
        final isFollowedBackResponse = await SupabaseConfig.client
            .from('follows')
            .select()
            .eq('follower_id', userId)
            .eq('following_id', currentUserId);
        
        final isFollowedBack = isFollowedBackResponse.isNotEmpty;
        
        _friendshipStatus[userId] = isCurrentUserFollowing && isFollowedBack;
      }
      
      print('Статусы дружбы загружены для ${_friendshipStatus.length} пользователей');
    } catch (e) {
      print('Error checking friendship status: $e');
    }
  }

  Future<void> _toggleFollow(String userId, bool currentlyFollowing) async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) return;

    if (currentUserId == userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нельзя подписаться на себя'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      if (currentlyFollowing) {
        await SupabaseConfig.client
            .from('follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', userId);
      } else {
        await SupabaseConfig.client.from('follows').insert({
          'follower_id': currentUserId,
          'following_id': userId,
        });
      }

      setState(() {
        _followingStatus[userId] = !currentlyFollowing;
        
        _checkFriendshipStatusForUser(userId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyFollowing ? 'Вы отписались' : 'Вы подписались',
          ),
          backgroundColor: currentlyFollowing ? Colors.grey : Colors.green,
        ),
      );
    } catch (e) {
      print('Error toggling follow: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _checkFriendshipStatusForUser(String userId) async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null || currentUserId == userId) return;

    try {
      final isFollowingResponse = await SupabaseConfig.client
          .from('follows')
          .select()
          .eq('follower_id', currentUserId)
          .eq('following_id', userId);
      
      final isCurrentUserFollowing = isFollowingResponse.isNotEmpty;
      
      final isFollowedBackResponse = await SupabaseConfig.client
          .from('follows')
          .select()
          .eq('follower_id', userId)
          .eq('following_id', currentUserId);
      
      final isFollowedBack = isFollowedBackResponse.isNotEmpty;
      
      setState(() {
        _friendshipStatus[userId] = isCurrentUserFollowing && isFollowedBack;
      });
    } catch (e) {
      print('Error checking friendship status for user: $e');
    }
  }

  void _openUserProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OtherProfileScreen(userId: userId),
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
        title: Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.blueAccent,
              ),
            )
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.type == 'followers'
                            ? Icons.group
                            : Icons.person_outline,
                        size: 80,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.type == 'followers'
                            ? 'Нет подписчиков'
                            : 'Нет подписок',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40.0),
                        child: Text(
                          widget.type == 'followers'
                              ? 'Пользователи, которые подпишутся на вас, появятся здесь'
                              : 'Пользователи, на которых вы подпишетесь, появятся здесь',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadUsers,
                  backgroundColor: Colors.white,
                  color: Colors.blueAccent,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final currentUserId = SupabaseConfig.auth.currentUser?.id;
                      final isCurrentUser = currentUserId == user['id'];
                      final isFollowing = _followingStatus[user['id']] ?? false;
                      final isFriend = _friendshipStatus[user['id']] ?? false;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () => _openUserProfile(user['id']),
                                child: CircleAvatar(
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
                              ),
                              
                              const SizedBox(width: 12),
                              
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _openUserProfile(user['id']),
                                      child: Text(
                                        '@${user['username']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    
                                    if (user['bio'] != null && user['bio'].isNotEmpty)
                                      GestureDetector(
                                        onTap: () => _openUserProfile(user['id']),
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            user['bio'],
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 13,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(width: 12),
                              
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isCurrentUser)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Вы',
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  else
                                    ElevatedButton(
                                      onPressed: () =>
                                          _toggleFollow(user['id'], isFollowing),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isFollowing
                                            ? Colors.grey[200]
                                            : Colors.blueAccent,
                                        foregroundColor: isFollowing
                                            ? Colors.black87
                                            : Colors.white,
                                        side: isFollowing
                                            ? BorderSide(color: Colors.grey[300]!)
                                            : null,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        elevation: 0,
                                      ),
                                      child: Text(
                                        isFollowing ? 'Отписаться' : 'Подписаться',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  
                                  if (!isCurrentUser && isFriend)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          'Друг',
                                          style: TextStyle(
                                            color: Colors.green[700],
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}