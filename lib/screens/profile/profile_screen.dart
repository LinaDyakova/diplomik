import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:vroom/supabase/supabase_config.dart';
import '../post/post_detail_screen.dart';
import '../follow/follow_list_screen.dart';
import '../notifications/notifications_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  int _followersCount = 0;
  int _followingCount = 0;
  int _unreadNotificationsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profileResponse = await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      final postsResponse = await SupabaseConfig.client
          .from('posts')
          .select('*, likes(count), comments(count)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final statsResponse = await SupabaseConfig.client
          .rpc('get_profile_stats', params: {'user_id': userId});

      int postsCount = 0;
      int followersCount = 0;
      int followingCount = 0;

      if (statsResponse != null) {
        final stats = statsResponse as Map<String, dynamic>;
        postsCount = (stats['posts_count'] ?? 0) as int;
        followersCount = (stats['followers_count'] ?? 0) as int;
        followingCount = (stats['following_count'] ?? 0) as int;
      } else {
        final followersResponse = await SupabaseConfig.client
            .from('follows')
            .select('id')
            .eq('following_id', userId);
        final followingResponse = await SupabaseConfig.client
            .from('follows')
            .select('id')
            .eq('follower_id', userId);
        followersCount = followersResponse.length;
        followingCount = followingResponse.length;
        postsCount = postsResponse.length;
      }

      setState(() {
        _profile = profileResponse;
        _posts = List<Map<String, dynamic>>.from(postsResponse);
        _followersCount = followersCount;
        _followingCount = followingCount;
        _isLoading = false;
      });
      await _loadUnreadNotificationsCount();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    await showDialog(
      context: context,
      builder: (context) => UpdateProfileDialog(
        profile: _profile!,
        onUpdated: _loadProfileData,
      ),
    );
  }

  Future<void> _loadUnreadNotificationsCount() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await SupabaseConfig.client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      setState(() {
        _unreadNotificationsCount = (response as List).length;
      });
    } catch (e) {
      print('Error loading unread notifications count: $e');
    }
  }

  Future<void> _addPost() async {
    await showDialog(
      context: context,
      builder: (context) => AddPostDialog(onAdded: _loadProfileData),
    );
  }

  Future<void> _logout() async {
    try {
      await SupabaseConfig.auth.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/signin');
      }
    } catch (e) {
      print('Error logging out: $e');
    }
  }

  void _openFollowersList() {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FollowListScreen(
            userId: userId,
            type: 'followers',
            title: 'Подписчики',
          ),
        ),
      );
    }
  }

  void _openFollowingList() {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FollowListScreen(
            userId: userId,
            type: 'following',
            title: 'Подписки',
          ),
        ),
      );
    }
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
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.black87)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text('Профиль', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        actions: [
          IconButton(
            onPressed: _addPost,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            color: Colors.black87,
            tooltip: 'Добавить пост',
          ),
          Stack(
            children: [
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                  ).then((_) => _loadUnreadNotificationsCount());
                },
                icon: const Icon(Icons.notifications_outlined),
                color: Colors.black87,
                tooltip: 'Уведомления',
              ),
              if (_unreadNotificationsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text(
                      _unreadNotificationsCount > 9 ? '9+' : _unreadNotificationsCount.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 8),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_outlined),
            color: Colors.black87,
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfileData,
        color: Colors.black87,
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileHeader(),
              _buildStatsSection(),
              _buildPostsGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.only(bottom: 8.0),
      child: Row(
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
                    child: Text(_profile!['bio'], style: const TextStyle(fontSize: 14, color: Colors.black87)),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _updateProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text('Редактировать профиль'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      margin: const EdgeInsets.only(bottom: 8.0),
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
            onTap: _openFollowersList,
            child: Column(
              children: [
                Text(_followersCount.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Подписчиков', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              ],
            ),
          ),
          GestureDetector(
            onTap: _openFollowingList,
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
    );
  }

  Widget _buildPostsGrid() {
    if (_posts.isEmpty) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 60.0),
        child: Column(
          children: [
            Icon(Icons.photo_library_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text('Пока нет постов', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Text(
                'Добавьте первый пост, нажав на иконку камеры в правом верхнем углу',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500]),
              ),
            ),
          ],
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

// Обновлённые диалоги (UpdateProfileDialog, AddPostDialog) в том же файле,
// но для краткости покажу изменения в стилях, остальной код без изменений.

class UpdateProfileDialog extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onUpdated;

  const UpdateProfileDialog({super.key, required this.profile, required this.onUpdated});

  @override
  State<UpdateProfileDialog> createState() => _UpdateProfileDialogState();
}

class _UpdateProfileDialogState extends State<UpdateProfileDialog> {
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  XFile? _image;
  Uint8List? _imageBytes;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _usernameController.text = widget.profile['username'] ?? '';
    _bioController.text = widget.profile['bio'] ?? '';
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _image = image;
      });
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
      }
    }
  }

  Widget _buildAvatarPreview() {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey[400]!, width: 3),
          ),
          child: Stack(
            children: [
              if (_image != null)
                kIsWeb && _imageBytes != null
                    ? CircleAvatar(radius: 58, backgroundImage: MemoryImage(_imageBytes!))
                    : CircleAvatar(radius: 58, backgroundImage: FileImage(File(_image!.path)))
              else if (widget.profile['avatar_url'] != null)
                CircleAvatar(radius: 58, backgroundImage: NetworkImage(widget.profile['avatar_url']))
              else
                CircleAvatar(radius: 58, backgroundColor: Colors.grey[300], child: const Icon(Icons.person, size: 50, color: Colors.grey)),
              if (_isUploadingImage)
                const Positioned.fill(
                  child: Center(child: CircularProgressIndicator(color: Colors.black87)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.photo_camera, size: 18, color: Colors.black87),
          label: const Text('Сменить аватар', style: TextStyle(color: Colors.black87)),
        ),
      ],
    );
  }

  Future<String?> _uploadAvatar() async {
    if (_image == null) return null;
    try {
      setState(() => _isUploadingImage = true);
      final userId = widget.profile['id'];
      final fileExtension = _image!.name.split('.').last;
      final fileName = 'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      if (widget.profile['avatar_url'] != null) {
        try {
          final oldFileName = widget.profile['avatar_url'].split('/').last;
          await SupabaseConfig.client.storage.from('avatars').remove([oldFileName]);
        } catch (e) {}
      }

      if (kIsWeb && _imageBytes != null) {
        await SupabaseConfig.client.storage.from('avatars').uploadBinary(fileName, _imageBytes!);
      } else if (!kIsWeb) {
        await SupabaseConfig.client.storage.from('avatars').upload(fileName, File(_image!.path));
      }

      return SupabaseConfig.client.storage.from('avatars').getPublicUrl(fileName);
    } catch (e) {
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите имя пользователя'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      String? newAvatarUrl;
      if (_image != null) {
        newAvatarUrl = await _uploadAvatar();
      }

      final updateData = {
        'id': widget.profile['id'],
        'username': _usernameController.text.trim(),
        'bio': _bioController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (newAvatarUrl != null) {
        updateData['avatar_url'] = newAvatarUrl;
      }

      await SupabaseConfig.client.from('profiles').upsert(updateData);
      widget.onUpdated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль обновлен'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Редактировать профиль', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black87)),
              const SizedBox(height: 20),
              _buildAvatarPreview(),
              const SizedBox(height: 20),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Имя пользователя*',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bioController,
                decoration: InputDecoration(
                  labelText: 'Биография',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                  hintText: 'Расскажите о себе...',
                ),
                maxLines: 4,
                minLines: 3,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Сохранить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddPostDialog extends StatefulWidget {
  final VoidCallback onAdded;
  const AddPostDialog({super.key, required this.onAdded});

  @override
  State<AddPostDialog> createState() => _AddPostDialogState();
}

class _AddPostDialogState extends State<AddPostDialog> {
  final _contentController = TextEditingController();
  XFile? _image;
  Uint8List? _imageBytes;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  bool _imageSelected = false;

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image != null) {
      setState(() {
        _image = image;
        _imageSelected = true;
      });
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
      }
    }
  }

  Widget _buildImagePreview() {
    if (!_imageSelected) {
      return GestureDetector(
        onTap: _pickImage,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!, width: 2),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate, color: Colors.grey, size: 50),
                SizedBox(height: 12),
                Text('Добавить фото*', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 8),
                Text('Нажмите, чтобы выбрать изображение', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }
    // аналогичный код для превью с крестиком (без изменений, но с черным CircularProgressIndicator)
    if (_image != null) {
      if (kIsWeb && _imageBytes != null) {
        return Stack(
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_imageBytes!, fit: BoxFit.cover, width: double.infinity, height: 200),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _image = null;
                    _imageBytes = null;
                    _imageSelected = false;
                  });
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                  child: const Icon(Icons.close, size: 18, color: Colors.red),
                ),
              ),
            ),
          ],
        );
      } else if (!kIsWeb) {
        // аналогично с FileImage
      }
    }
    return Container();
  }

  Future<void> _addPost() async {
    // логика без изменений, но индикатор загрузки черный
    // ...
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Новый пост', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black87)),
                const SizedBox(height: 20),
                _buildImagePreview(),
                const SizedBox(height: 16),
                TextField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    labelText: 'Описание',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey[50],
                    hintText: 'Расскажите о чем-нибудь интересном...',
                  ),
                  maxLines: 4,
                  minLines: 3,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _addPost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Опубликовать'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}