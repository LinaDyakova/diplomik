import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vroom/screens/profile/other_profile_screen.dart';
import 'package:vroom/supabase/supabase_config.dart';
import '../post/post_detail_screen.dart';

class MainFeedScreen extends StatefulWidget {
  const MainFeedScreen({super.key});

  @override
  State<MainFeedScreen> createState() => _MainFeedScreenState();
}

class _MainFeedScreenState extends State<MainFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.trim().isNotEmpty) {
        _performSearch(_searchController.text.trim());
      } else {
        setState(() {
          _searchResults.clear();
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults.clear();
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final response = await SupabaseConfig.client
          .from('profiles')
          .select('''
            id, username, avatar_url, bio,
            posts(count),
            follows!follows_follower_id_fkey(count)
          ''')
          .ilike('username', '%$query%')
          .limit(10);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(response);
        _isSearching = false;
      });
    } catch (e) {
      print('Error searching users: $e');
      setState(() => _isSearching = false);
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

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
        _searchResults.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Поиск пользователей...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey[500]),
                ),
                style: const TextStyle(fontSize: 16),
              )
            : const Text(
                'VROOM',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  fontSize: 22,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
            color: Colors.black87,
          ),
        ],
        bottom: _showSearch ? null : TabBar(
          controller: _tabController,
          indicatorColor: Colors.blueAccent,
          indicatorWeight: 3,
          labelColor: Colors.black87,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Общая'),
            Tab(text: 'Подписки'),
            Tab(text: 'Друзья'),
          ],
        ),
      ),
      body: _showSearch
          ? _buildSearchResults()
          : Container(
              color: Colors.grey[100],
              child: TabBarView(
                controller: _tabController,
                children: const [
                  GeneralFeedTab(),
                  FollowingFeedTab(),
                  FriendsFeedTab(),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.blueAccent,
        ),
      );
    }

    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 20),
            Text(
              'Начните вводить имя пользователя',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 20),
            Text(
              'Пользователи не найдены',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final postsCount = user['posts']?[0]?['count'] ?? 0;
        final followersCount = user['follows']?[0]?['count'] ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            leading: CircleAvatar(
              radius: 28,
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
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user['bio'] != null && user['bio'].isNotEmpty)
                  Padding(
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatItem('Посты', postsCount.toString()),
                    const SizedBox(width: 16),
                    _buildStatItem('Подписчики', followersCount.toString()),
                  ],
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Профиль',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            onTap: () => _openUserProfile(user['id']),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class GeneralFeedTab extends StatefulWidget {
  const GeneralFeedTab({super.key});

  @override
  State<GeneralFeedTab> createState() => _GeneralFeedTabState();
}

class _GeneralFeedTabState extends State<GeneralFeedTab> {
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  Set<int> _likedPosts = {};

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadUserLikes();
  }

  Future<void> _loadPosts() async {
    try {
      final response = await SupabaseConfig.client
          .from('posts')
          .select('''
            *,
            profiles!posts_user_id_fkey(username, avatar_url),
            likes(count),
            comments(count)
          ''')
          .order('created_at', ascending: false);

      setState(() {
        _posts = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading posts: $e');
    }
  }

  Future<void> _loadUserLikes() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await SupabaseConfig.client
          .from('likes')
          .select('post_id')
          .eq('user_id', userId);

      setState(() {
        _likedPosts = Set.from(response.map((like) => like['post_id'] as int));
      });
    } catch (e) {
      print('Error loading user likes: $e');
    }
  }

  Future<void> _refreshData() async {
    await _loadPosts();
    await _loadUserLikes();
  }

  void _openPostDetail(int postId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(postId: postId),
      ),
    );
  }

  Future<void> _likePost(int postId, bool currentlyLiked) async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      if (currentlyLiked) {
        await SupabaseConfig.client
            .from('likes')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', postId);
      } else {
        await SupabaseConfig.client.from('likes').upsert({
          'user_id': userId,
          'post_id': postId,
        });
      }

      setState(() {
        if (currentlyLiked) {
          _likedPosts.remove(postId);
        } else {
          _likedPosts.add(postId);
        }
      });

      await _loadPosts();
    } catch (e) {
      print('Error toggling like: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.blueAccent,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      backgroundColor: Colors.white,
      color: Colors.blueAccent,
      child: ListView.builder(
        itemCount: _posts.length,
        padding: const EdgeInsets.all(8.0),
        itemBuilder: (context, index) {
          final post = _posts[index];
          final isLiked = _likedPosts.contains(post['id']);
          return _buildPostCard(post, isLiked);
        },
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, bool isLiked) {
    final postId = post['id'];
    final likesCount = post['likes']?[0]?['count'] ?? 0;
    final commentsCount = post['comments']?[0]?['count'] ?? 0;

    return GestureDetector(
      onTap: () => _openPostDetail(postId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.0),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: post['profiles']?['avatar_url'] != null
                        ? NetworkImage(post['profiles']['avatar_url'])
                        : null,
                    child: post['profiles']?['avatar_url'] == null
                        ? const Icon(
                            Icons.person,
                            color: Colors.grey,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${post['profiles']?['username'] ?? 'Пользователь'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (post['content'] != null && post['content'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  post['content'],
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                ),
              ),

            if (post['photo_url'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.zero,
                    bottom: Radius.circular(20.0),
                  ),
                  child: Container(
                    color: Colors.grey[100],
                    child: Image.network(
                      post['photo_url'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 280,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 280,
                          color: Colors.grey[200],
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.blueAccent,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 280,
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(
                              Icons.photo,
                              size: 60,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      _likePost(postId, isLiked);
                    },
                    icon: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.red : Colors.grey[600],
                      size: 26,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    likesCount.toString(),
                    style: TextStyle(
                      color: isLiked ? Colors.red : Colors.grey[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 24),

                  const Icon(
                    Icons.comment_outlined,
                    color: Colors.grey,
                    size: 26,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    commentsCount.toString(),
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
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

class FollowingFeedTab extends StatefulWidget {
  const FollowingFeedTab({super.key});

  @override
  State<FollowingFeedTab> createState() => _FollowingFeedTabState();
}

class _FollowingFeedTabState extends State<FollowingFeedTab> {
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  Set<int> _likedPosts = {};

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadUserLikes();
  }

  Future<void> _loadPosts() async {
    try {
      final userId = SupabaseConfig.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final followingResponse = await SupabaseConfig.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', userId);

      if (followingResponse.isEmpty) {
        setState(() {
          _posts = [];
          _isLoading = false;
        });
        return;
      }

      final followingIds = followingResponse
          .map((item) => item['following_id'] as String)
          .toList();

      final response = await SupabaseConfig.client
          .from('posts')
          .select('''
            *,
            profiles!posts_user_id_fkey(username, avatar_url),
            likes(count),
            comments(count)
          ''')
          .inFilter('user_id', followingIds)
          .order('created_at', ascending: false);

      setState(() {
        _posts = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading following posts: $e');
    }
  }

  Future<void> _loadUserLikes() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await SupabaseConfig.client
          .from('likes')
          .select('post_id')
          .eq('user_id', userId);

      setState(() {
        _likedPosts = Set.from(response.map((like) => like['post_id'] as int));
      });
    } catch (e) {
      print('Error loading user likes: $e');
    }
  }

  Future<void> _refreshData() async {
    await _loadPosts();
    await _loadUserLikes();
  }

  void _openPostDetail(int postId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(postId: postId),
      ),
    );
  }

  Future<void> _likePost(int postId, bool currentlyLiked) async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      if (currentlyLiked) {
        await SupabaseConfig.client
            .from('likes')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', postId);
      } else {
        await SupabaseConfig.client.from('likes').upsert({
          'user_id': userId,
          'post_id': postId,
        });
      }

      setState(() {
        if (currentlyLiked) {
          _likedPosts.remove(postId);
        } else {
          _likedPosts.add(postId);
        }
      });

      await _loadPosts();
    } catch (e) {
      print('Error toggling like: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.blueAccent,
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 20),
            const Text(
              'Нет постов от подписок',
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
                'Подпишитесь на пользователей, чтобы видеть их посты здесь',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                final mainState = context.findAncestorStateOfType<_MainFeedScreenState>();
                mainState?._toggleSearch();
              },
              icon: const Icon(Icons.search),
              label: const Text('Найти пользователей'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      backgroundColor: Colors.white,
      color: Colors.blueAccent,
      child: ListView.builder(
        itemCount: _posts.length,
        padding: const EdgeInsets.all(8.0),
        itemBuilder: (context, index) {
          final post = _posts[index];
          final isLiked = _likedPosts.contains(post['id']);
          return _buildPostCard(post, isLiked);
        },
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, bool isLiked) {
    final postId = post['id'];
    final likesCount = post['likes']?[0]?['count'] ?? 0;
    final commentsCount = post['comments']?[0]?['count'] ?? 0;

    return GestureDetector(
      onTap: () => _openPostDetail(postId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.0),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: post['profiles']?['avatar_url'] != null
                        ? NetworkImage(post['profiles']['avatar_url'])
                        : null,
                    child: post['profiles']?['avatar_url'] == null
                        ? const Icon(
                            Icons.person,
                            color: Colors.grey,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${post['profiles']?['username'] ?? 'Пользователь'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (post['content'] != null && post['content'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  post['content'],
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                ),
              ),

            if (post['photo_url'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.zero,
                    bottom: Radius.circular(20.0),
                  ),
                  child: Container(
                    color: Colors.grey[100],
                    child: Image.network(
                      post['photo_url'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 280,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 280,
                          color: Colors.grey[200],
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.blueAccent,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 280,
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(
                              Icons.photo,
                              size: 60,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      _likePost(postId, isLiked);
                    },
                    icon: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.red : Colors.grey[600],
                      size: 26,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    likesCount.toString(),
                    style: TextStyle(
                      color: isLiked ? Colors.red : Colors.grey[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 24),

                  const Icon(
                    Icons.comment_outlined,
                    color: Colors.grey,
                    size: 26,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    commentsCount.toString(),
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
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

class FriendsFeedTab extends StatefulWidget {
  const FriendsFeedTab({super.key});

  @override
  State<FriendsFeedTab> createState() => _FriendsFeedTabState();
}

class _FriendsFeedTabState extends State<FriendsFeedTab> {
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  Set<int> _likedPosts = {};

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadUserLikes();
  }

  Future<void> _loadPosts() async {
    try {
      final userId = SupabaseConfig.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final followingResponse = await SupabaseConfig.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', userId);

      final followersResponse = await SupabaseConfig.client
          .from('follows')
          .select('follower_id')
          .eq('following_id', userId);

      final followingIds = followingResponse
          .map((item) => item['following_id'] as String)
          .toSet();
      
      final followerIds = followersResponse
          .map((item) => item['follower_id'] as String)
          .toSet();

      final mutualFriends = followingIds.intersection(followerIds).toList();

      if (mutualFriends.isEmpty) {
        setState(() {
          _posts = [];
          _isLoading = false;
        });
        return;
      }

      final response = await SupabaseConfig.client
          .from('posts')
          .select('''
            *,
            profiles!posts_user_id_fkey(username, avatar_url),
            likes(count),
            comments(count)
          ''')
          .inFilter('user_id', mutualFriends)
          .order('created_at', ascending: false);

      setState(() {
        _posts = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading friends posts: $e');
    }
  }

  Future<void> _loadUserLikes() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await SupabaseConfig.client
          .from('likes')
          .select('post_id')
          .eq('user_id', userId);

      setState(() {
        _likedPosts = Set.from(response.map((like) => like['post_id'] as int));
      });
    } catch (e) {
      debugPrint('Error loading user likes: $e');
    }
  }

  Future<void> _refreshData() async {
    await _loadPosts();
    await _loadUserLikes();
  }

  void _openPostDetail(int postId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(postId: postId),
      ),
    );
  }

    Future<void> _likePost(int postId, bool currentlyLiked) async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      if (currentlyLiked) {
        await SupabaseConfig.client
            .from('likes')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', postId);
      } else {
        await SupabaseConfig.client.from('likes').upsert({
          'user_id': userId,
          'post_id': postId,
        });
      }

      setState(() {
        if (currentlyLiked) {
          _likedPosts.remove(postId);
        } else {
          _likedPosts.add(postId);
        }
      });

      await _loadPosts();
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.blueAccent,
        ),
      );
    } 

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 20),
            const Text(
              'Нет постов от друзей',
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
                'Найдите друзей и подпишитесь друг на друга, чтобы видеть их посты здесь',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                final mainState = context.findAncestorStateOfType<_MainFeedScreenState>();
                mainState?._toggleSearch();
              },
              icon: const Icon(Icons.search),
              label: const Text('Найти друзей'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      backgroundColor: Colors.white,
      color: Colors.blueAccent,
      child: ListView.builder(
        itemCount: _posts.length,
        padding: const EdgeInsets.all(8.0),
        itemBuilder: (context, index) {
          final post = _posts[index];
          final isLiked = _likedPosts.contains(post['id']);
          return _buildPostCard(post, isLiked);
        },
      ),
    );
  }

    Widget _buildPostCard(Map<String, dynamic> post, bool isLiked) {
    final postId = post['id'];
    final likesCount = post['likes']?[0]?['count'] ?? 0;
    final commentsCount = post['comments']?[0]?['count'] ?? 0;

    return GestureDetector(
      onTap: () => _openPostDetail(postId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.0),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: post['profiles']?['avatar_url'] != null
                        ? NetworkImage(post['profiles']['avatar_url'])
                        : null,
                    child: post['profiles']?['avatar_url'] == null
                        ? const Icon(
                            Icons.person,
                            color: Colors.grey,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${post['profiles']?['username'] ?? 'Пользователь'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (post['content'] != null && post['content'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  post['content'],
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                ),
              ),

            if (post['photo_url'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.zero,
                    bottom: Radius.circular(20.0),
                  ),
                  child: Container(
                    color: Colors.grey[100],
                    child: Image.network(
                      post['photo_url'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 280,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 280,
                          color: Colors.grey[200],
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.blueAccent,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 280,
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(
                              Icons.photo,
                              size: 60,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      _likePost(postId, isLiked);
                    },
                    icon: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.red : Colors.grey[600],
                      size: 26,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    likesCount.toString(),
                    style: TextStyle(
                      color: isLiked ? Colors.red : Colors.grey[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 24),

                  const Icon(
                    Icons.comment_outlined,
                    color: Colors.grey,
                    size: 26,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    commentsCount.toString(),
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
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