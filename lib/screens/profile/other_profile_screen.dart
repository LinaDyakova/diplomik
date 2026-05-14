import 'package:flutter/material.dart';
import 'package:vroom/screens/follow/follow_list_screen.dart';
import 'package:vroom/supabase/supabase_config.dart';
import '../post/post_detail_screen.dart';

class OtherProfileScreen extends StatefulWidget {
  final String userId;

  const OtherProfileScreen({super.key, required this.userId});

  @override
  State<OtherProfileScreen> createState() => _OtherProfileScreenState();
}

class _OtherProfileScreenState extends State<OtherProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFriend = false;
  int _followersCount = 0;
  int _followingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _checkIfFollowing();
  }

  Future<void> _loadProfileData() async {
    try {
      final profileResponse = await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('id', widget.userId)
          .single();

      final postsResponse = await SupabaseConfig.client
          .from('posts')
          .select('*, likes(count), comments(count)')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false);

      final followersResponse = await SupabaseConfig.client
          .from('follows')
          .select()
          .eq('following_id', widget.userId);

      final followingResponse = await SupabaseConfig.client
          .from('follows')
          .select()
          .eq('follower_id', widget.userId);

      final currentUserId = SupabaseConfig.auth.currentUser?.id;

      if (currentUserId != null && currentUserId != widget.userId) {
        final isFollowingResponse = await SupabaseConfig.client
            .from('follows')
            .select()
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId);

        final isFollowedBackResponse = await SupabaseConfig.client
            .from('follows')
            .select()
            .eq('follower_id', widget.userId)
            .eq('following_id', currentUserId);

        setState(() {
          _isFriend = isFollowingResponse.isNotEmpty && isFollowedBackResponse.isNotEmpty;
        });
      }

      setState(() {
        _profile = profileResponse;
        _posts = List<Map<String, dynamic>>.from(postsResponse);
        _followersCount = followersResponse.length;
        _followingCount = followingResponse.length;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading profile data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkIfFollowing() async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final response = await SupabaseConfig.client
          .from('follows')
          .select()
          .eq('follower_id', currentUserId)
          .eq('following_id', widget.userId);

      setState(() {
        _isFollowing = response.isNotEmpty;
      });
    } catch (e) {
      print('Error checking follow status: $e');
    }
  }

  Future<void> _checkFriendshipStatus() async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null || currentUserId == widget.userId) return;

    try {
      final isFollowingResponse = await SupabaseConfig.client
          .from('follows')
          .select()
          .eq('follower_id', currentUserId)
          .eq('following_id', widget.userId);

      final isFollowedBackResponse = await SupabaseConfig.client
          .from('follows')
          .select()
          .eq('follower_id', widget.userId)
          .eq('following_id', currentUserId);

      setState(() {
        _isFriend = isFollowingResponse.isNotEmpty && isFollowedBackResponse.isNotEmpty;
      });
    } catch (e) {
      print('Error checking friendship status: $e');
    }
  }

  Future<void> _toggleFollow() async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы подписаться'), backgroundColor: Colors.red),
      );
      return;
    }

    if (currentUserId == widget.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нельзя подписаться на себя'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      if (_isFollowing) {
        await SupabaseConfig.client
            .from('follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId);
      } else {
        await SupabaseConfig.client.from('follows').insert({
          'follower_id': currentUserId,
          'following_id': widget.userId,
        });
      }

      await _checkFriendshipStatus();

      setState(() {
        _isFollowing = !_isFollowing;
        _followersCount = _isFollowing ? _followersCount + 1 : _followersCount - 1;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFollowing ? 'Вы подписались' : 'Вы отписались'),
          backgroundColor: _isFollowing ? Colors.green : Colors.grey,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  void _openFollowersList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowListScreen(
          userId: widget.userId,
          type: 'followers',
          title: 'Подписчики',
        ),
      ),
    );
  }

  void _openFollowingList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowListScreen(
          userId: widget.userId,
          type: 'following',
          title: 'Подписки',
        ),
      ),
    );
  }

  void _openPostDetail(int postId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(postId: postId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          title: const Text('Профиль', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.black87)),
      );
    }

    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Профиль'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: Text('Пользователь не найден')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          '@${_profile!['username']}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfileData,
        color: Colors.black87,
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey[300]!, width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 38,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: _profile?['avatar_url'] != null
                                ? NetworkImage(_profile!['avatar_url'])
                                : null,
                            child: _profile?['avatar_url'] == null
                                ? const Icon(Icons.person, size: 40, color: Colors.grey)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${_profile?['username'] ?? 'Пользователь'}',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                              if (_profile?['bio'] != null && _profile!['bio'].isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    _profile!['bio'],
                                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _toggleFollow,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isFollowing ? Colors.grey[200] : Colors.black87,
                                        foregroundColor: _isFollowing ? Colors.black87 : Colors.white,
                                        side: _isFollowing ? BorderSide(color: Colors.grey[300]!) : null,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                      child: Text(_isFollowing ? 'Отписаться' : 'Подписаться'),
                                    ),
                                  ),
                                  if (_isFriend)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text('Друг', style: TextStyle(color: Colors.green[700], fontSize: 12)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey[200]!),
                    bottom: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(_posts.length.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Постов', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => _openFollowersList(),
                      child: Column(
                        children: [
                          Text(_followersCount.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Подписчиков', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _openFollowingList(),
                      child: Column(
                        children: [
                          Text(_followingCount.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Подписок', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildPostsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostsSection() {
    if (_posts.isEmpty) {
      return Container(
        color: Colors.white,
        height: MediaQuery.of(context).size.height * 0.4,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_outlined, size: 80, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text('Пока нет постов', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(4.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2.0,
          mainAxisSpacing: 2.0,
          childAspectRatio: 1.0,
        ),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          return GestureDetector(
            onTap: () => _openPostDetail(post['id']),
            child: Container(
              color: Colors.grey[50],
              child: post['photo_url'] != null
                  ? Image.network(
                      post['photo_url'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[100],
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.black87,
                                strokeWidth: 2,
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.photo_outlined, color: Colors.grey, size: 24)),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: const Center(child: Icon(Icons.photo_outlined, color: Colors.grey, size: 24)),
                    ),
            ),
          );
        },
      ),
    );
  }
}