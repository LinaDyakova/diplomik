import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vroom/screens/profile/edit_post_dialog.dart';
import 'package:vroom/screens/profile/other_profile_screen.dart';
import 'package:vroom/screens/profile/profile_screen.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'package:timeago/timeago.dart' as timeago;

class PostDetailScreen extends StatefulWidget {
  final int postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen>
    with TickerProviderStateMixin  {
  Map<String, dynamic>? _post;
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isLiked = false;
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isAddingComment = false;

  // Анимация лайка (всплеск)
  late AnimationController _likeAnimationController;
  late Animation<double> _likeScaleAnimation;
  late AnimationController _splashController;
  final List<_SplashParticle> _particles = [];

  @override
  void initState() {
    super.initState();
    _loadPostDetails();
    _checkIfLiked();
    timeago.setLocaleMessages('ru', timeago.RuMessages());

    // Настройка анимации масштаба
    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _likeScaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _likeAnimationController, curve: Curves.easeOutBack),
    );
    _likeAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _likeAnimationController.reverse();
      }
    });

    // Контроллер для частиц всплеска
    _splashController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Генерируем 6 частиц под разными углами
    for (int i = 0; i < 6; i++) {
      _particles.add(_SplashParticle(
        angle: (i * 60) * (pi / 180),
        color: Colors.red, // начальный цвет не важен, обновится в build
      ));
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _likeAnimationController.dispose();
    _splashController.dispose();
    super.dispose();
  }

  Future<void> _loadPostDetails() async {
    try {
      final postResponse = await SupabaseConfig.client
          .from('posts')
          .select('''
            *,
            profiles!posts_user_id_fkey(username, avatar_url),
            likes(count),
            comments(count)
          ''')
          .eq('id', widget.postId)
          .single();

      final commentsResponse = await SupabaseConfig.client
          .from('comments')
          .select('''
            *,
            profiles!comments_user_id_fkey(username, avatar_url)
          ''')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: true);

      setState(() {
        _post = postResponse;
        _comments = List<Map<String, dynamic>>.from(commentsResponse);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading post details: $e');
    }
  }

  Future<void> _checkIfLiked() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await SupabaseConfig.client
          .from('likes')
          .select()
          .eq('user_id', userId)
          .eq('post_id', widget.postId);

      setState(() {
        _isLiked = response.isNotEmpty;
      });
    } catch (e) {
      print('Error checking like: $e');
    }
  }

  Future<void> _toggleLike() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Войдите, чтобы ставить лайки'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Запуск анимации масштаба и всплеска
    _likeAnimationController.forward();
    _splashController.reset();
    _splashController.forward();

    try {
      if (_isLiked) {
        await SupabaseConfig.client
            .from('likes')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', widget.postId);
      } else {
        await SupabaseConfig.client.from('likes').insert({
          'user_id': userId,
          'post_id': widget.postId,
        });
      }

      setState(() {
        _isLiked = !_isLiked;
        if (_post != null) {
          final currentCount = _post!['likes'][0]['count'] ?? 0;
          _post!['likes'][0]['count'] = _isLiked ? currentCount + 1 : currentCount - 1;
        }
        // Обновляем цвета частиц в соответствии с новым состоянием
        for (var particle in _particles) {
          particle.color = _isLiked ? Colors.red : Colors.grey[600]!;
        }
      });
    } catch (e) {
      print('Error toggling like: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _addComment() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Войдите, чтобы оставлять комментарии'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final commentText = _commentController.text.trim();
    if (commentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите текст комментария'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isAddingComment) return;

    setState(() {
      _isAddingComment = true;
    });

    try {
      await SupabaseConfig.client.from('comments').insert({
        'user_id': userId,
        'post_id': widget.postId,
        'content': commentText,
      });

      _commentController.clear();
      await _loadPostDetails();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Комментарий добавлен'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error adding comment: $e');
      String errorMessage = e is PostgrestException
          ? 'Ошибка базы данных: ${e.message}'
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при отправке: $errorMessage'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isAddingComment = false;
      });
    }
  }

  Future<void> _editPost() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await showDialog(
        context: context,
        builder: (context) => EditPostDialog(
          post: _post!,
          onUpdated: () {
            _loadPostDetails();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Пост обновлен'),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить пост?'),
        content: const Text('Это действие нельзя отменить.'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupabaseConfig.client.from('posts').delete().eq('id', widget.postId);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Пост удален'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка удаления: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openUserProfile(String userId) {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == userId) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ProfileScreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => OtherProfileScreen(userId: userId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            splashRadius: 20,
          ),
        ),
        title: const Text(
          'Публикация',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.black87),
            )
          : _post == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 60, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Пост не найден',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverToBoxAdapter(child: _buildPostHeader()),
                          SliverToBoxAdapter(child: _buildPostContent()),
                          SliverToBoxAdapter(child: _buildPostStats()),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index == 0) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 16, top: 8),
                                      child: Row(
                                        children: [
                                          const Text(
                                            'Комментарии',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black87.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              _comments.length.toString(),
                                              style: const TextStyle(
                                                color: Colors.black87,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final commentIndex = index - 1;
                                  if (commentIndex < _comments.length) {
                                    return _buildCommentItem(_comments[commentIndex]);
                                  }
                                  return null;
                                },
                                childCount: _comments.length + 1,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 80)),
                        ],
                      ),
                    ),
                    _buildCommentInput(),
                  ],
                ),
    );
  }

  Widget _buildPostHeader() {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    final isCreator = currentUserId == _post!['user_id'];
    final postDate = _post!['created_at'] != null
        ? timeago.format(DateTime.parse(_post!['created_at']), locale: 'ru')
        : 'Недавно';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openUserProfile(_post!['user_id']),
            child: CircleAvatar(
              radius: 25,
              backgroundColor: Colors.grey[200],
              backgroundImage: _post!['profiles']?['avatar_url'] != null
                  ? NetworkImage(_post!['profiles']['avatar_url'])
                  : null,
              child: _post!['profiles']?['avatar_url'] == null
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _openUserProfile(_post!['user_id']),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${_post!['profiles']?['username'] ?? 'Пользователь'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    postDate,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (isCreator)
            IconButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.black87.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.edit, color: Colors.black87, size: 20),
                          ),
                          title: const Text('Редактировать пост'),
                          onTap: () {
                            Navigator.pop(context);
                            _editPost();
                          },
                        ),
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete, color: Colors.red, size: 20),
                          ),
                          title: const Text('Удалить пост', style: TextStyle(color: Colors.red)),
                          onTap: () {
                            Navigator.pop(context);
                            _deletePost();
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                );
              },
              icon: Icon(Icons.more_horiz, color: Colors.grey[600], size: 24),
            ),
        ],
      ),
    );
  }

  Widget _buildPostContent() {
    final post = _post!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post['content'] != null && post['content'].isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              post['content'],
              style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
            ),
          ),
        if (post['photo_url'] != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.network(
                  post['photo_url'],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 380,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 380,
                      color: Colors.grey[100],
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.black87,
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
                      height: 380,
                      color: Colors.grey[100],
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo, size: 50, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('Ошибка загрузки изображения'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPostStats() {
    final likesCount = _post!['likes']?[0]?['count'] ?? 0;
    final commentsCount = _post!['comments']?[0]?['count'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Лайк с анимацией всплеска
          _buildAnimatedLikeButton(),
          // Комментарии
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black87.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.comment, color: Colors.black87, size: 20),
              ),
              const SizedBox(height: 4),
              Text(
                '$commentsCount',
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Комментарии',
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Виджет анимированной кнопки лайка с эффектом всплеска
  Widget _buildAnimatedLikeButton() {
    return Column(
      children: [
        GestureDetector(
          onTap: _toggleLike,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Частицы всплеска
                ...List.generate(_particles.length, (index) {
                  return AnimatedBuilder(
                    animation: _splashController,
                    builder: (context, child) {
                      final progress = _splashController.value;
                      if (progress == 0.0) return const SizedBox.shrink();
                      final opacity = (1 - progress).clamp(0.0, 1.0);
                      final scale = 0.5 + progress * 1.5;
                      final particle = _particles[index];
                      final dx = cos(particle.angle) * 12 * progress;
                      final dy = sin(particle.angle) * 12 * progress;

                      return Transform.translate(
                        offset: Offset(dx, dy),
                        child: Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: particle.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
                // Сердечко с масштабированием
                AnimatedBuilder(
                  animation: _likeScaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _likeScaleAnimation.value,
                      child: Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? Colors.red : Colors.grey[600],
                        size: 26,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_post!['likes']?[0]?['count'] ?? 0}',
          style: TextStyle(
            color: _isLiked ? Colors.red : Colors.grey[700],
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text('Нравится', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
      ],
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final commentDate = comment['created_at'] != null
        ? timeago.format(DateTime.parse(comment['created_at']), locale: 'ru')
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openUserProfile(comment['user_id']),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[200],
              backgroundImage: comment['profiles']?['avatar_url'] != null
                  ? NetworkImage(comment['profiles']['avatar_url'])
                  : null,
              child: comment['profiles']?['avatar_url'] == null
                  ? const Icon(Icons.person, size: 16, color: Colors.grey)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => _openUserProfile(comment['user_id']),
                            child: Text(
                              '@${comment['profiles']?['username'] ?? 'Пользователь'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            commentDate,
                            style: TextStyle(color: Colors.grey[500], fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        comment['content'],
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    final hasText = _commentController.text.trim().isNotEmpty;
    final isActive = hasText && !_isAddingComment;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        hintText: 'Написать комментарий...',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      maxLines: 1,
                      onChanged: (text) {
                        setState(() {});
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.black87 : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: _isAddingComment
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : IconButton(
                              onPressed: isActive ? _addComment : null,
                              icon: Icon(
                                Icons.send,
                                size: 18,
                                color: isActive ? Colors.white : Colors.grey[500],
                              ),
                              padding: EdgeInsets.zero,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Модель частицы для анимации всплеска
class _SplashParticle {
  final double angle;
  Color color;
  _SplashParticle({required this.angle, required this.color});
}