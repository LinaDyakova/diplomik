import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vroom/supabase/supabase_config.dart';

class CreateGroupChatScreen extends StatefulWidget {
  const CreateGroupChatScreen({super.key});

  @override
  State<CreateGroupChatScreen> createState() => _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends State<CreateGroupChatScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _chatType = 'group'; 
  List<String> _selectedParticipants = [];
  List<Map<String, dynamic>> _friends = []; 
  bool _isLoading = false;

  XFile? _image;
  Uint8List? _imageBytes;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) return;
    try {
      final followingResponse = await SupabaseConfig.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', currentUserId);
      final followingIds = followingResponse.map((f) => f['following_id'] as String).toList();

      final followersResponse = await SupabaseConfig.client
          .from('follows')
          .select('follower_id')
          .eq('following_id', currentUserId);
      final followerIds = followersResponse.map((f) => f['follower_id'] as String).toList();

      final friendIds = followingIds.toSet().intersection(followerIds.toSet()).toList();

      if (friendIds.isEmpty) {
        setState(() => _friends = []);
        return;
      }

      final profilesResponse = await SupabaseConfig.client
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', friendIds);
      final friends = profilesResponse.map((p) {
        return {
          'id': p['id'],
          'username': p['username'],
          'avatar_url': p['avatar_url'],
        };
      }).toList();
      setState(() => _friends = friends);
    } catch (e) {
      print('Error loading friends: $e');
    }
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
      } else {
        setState(() {
          _image = image;
        });
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (kIsWeb) {
      if (_imageBytes == null) return null;
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'group_${timestamp}_${timestamp}.jpg';
        await SupabaseConfig.client.storage
            .from('group-avatars')
            .uploadBinary(fileName, _imageBytes!,
                fileOptions: const FileOptions(contentType: 'image/jpeg'));
        return SupabaseConfig.client.storage
            .from('group-avatars')
            .getPublicUrl(fileName);
      } catch (e) {
        print('Image upload error (web): $e');
        return null;
      }
    } else {
      if (_image == null) return null;
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'group_${timestamp}_${_image!.path.split('/').last}';
        await SupabaseConfig.client.storage
            .from('group-avatars')
            .upload(fileName, File(_image!.path));
        return SupabaseConfig.client.storage
            .from('group-avatars')
            .getPublicUrl(fileName);
      } catch (e) {
        print('Image upload error: $e');
        return null;
      }
    }
  }

  Future<void> _createChat() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название')),
      );
      return;
    }
    if (_chatType == 'group' && _selectedParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одного участника')),
      );
      return;
    }
    setState(() => _isLoading = true);

    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) {
      setState(() => _isLoading = false);
      return;
    }

    String? photoUrl;
    if ((_image != null || _imageBytes != null)) {
      photoUrl = await _uploadImage();
    }

    try {
      final response = await SupabaseConfig.client.rpc('create_group_chat', params: {
        'p_creator_id': currentUserId,
        'p_type': _chatType,
        'p_group_name': _nameController.text.trim(),
        'p_group_photo_url': photoUrl,
        'p_participant_ids': _chatType == 'group' ? _selectedParticipants : [],
      });
      if (response != null) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Error creating chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text('Создать чат', style: TextStyle(color: Colors.black87)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createChat,
            child: const Text('Создать', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: kIsWeb
                              ? (_imageBytes != null ? MemoryImage(_imageBytes!) : null)
                              : (_image != null ? FileImage(File(_image!.path)) : null),
                          child: (_image == null && _imageBytes == null)
                              ? const Icon(Icons.group, size: 50, color: Colors.grey)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Тип чата', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'group', label: Text('Группа'), icon: Icon(Icons.group)),
                      ButtonSegment(value: 'channel', label: Text('Канал'), icon: Icon(Icons.mic)),
                    ],
                    selected: {_chatType},
                    onSelectionChanged: (Set<String> selection) {
                      setState(() {
                        _chatType = selection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_chatType == 'group')
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Участники', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _friends.isEmpty
                            ? const Text('Нет друзей', style: TextStyle(color: Colors.grey))
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _friends.length,
                                itemBuilder: (context, index) {
                                  final user = _friends[index];
                                  final isSelected = _selectedParticipants.contains(user['id']);
                                  return CheckboxListTile(
                                    title: Text('@${user['username']}'),
                                    value: isSelected,
                                    onChanged: (selected) {
                                      setState(() {
                                        if (selected == true) {
                                          _selectedParticipants.add(user['id']);
                                        } else {
                                          _selectedParticipants.remove(user['id']);
                                        }
                                      });
                                    },
                                    controlAffinity: ListTileControlAffinity.leading,
                                  );
                                },
                              ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}