import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:vroom/supabase/supabase_config.dart';

class EditPostDialog extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onUpdated;

  const EditPostDialog({
    super.key,
    required this.post,
    required this.onUpdated,
  });

  @override
  State<EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<EditPostDialog> {
  final _contentController = TextEditingController();
  XFile? _image;
  Uint8List? _imageBytes;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  bool _isDeletingImage = false;

  @override
  void initState() {
    super.initState();
    print('EditPostDialog initialized for post ID: ${widget.post['id']}');
    print('Post content: ${widget.post['content']}');
    print('Post photo_url: ${widget.post['photo_url']}');
    _contentController.text = widget.post['content'] ?? '';
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

  Widget _buildImagePreview() {
  // Если выбрано новое изображение
  if (_image != null) {
    if (kIsWeb) {
      if (_imageBytes != null) {
        return Stack(
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      _image = null;
                      _imageBytes = null;
                    });
                  },
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        );
      }
    } else {
      return Stack(
        children: [
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_image!.path),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  setState(() {
                    _image = null;
                  });
                },
                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      );
    }
  }

  // Если есть старое изображение и не удалено
  if (widget.post['photo_url'] != null && !_isDeletingImage) {
    return Stack(
      children: [
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              widget.post['photo_url'],
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
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
                  color: Colors.grey[200],
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.grey, size: 40),
                        SizedBox(height: 8),
                        Text('Ошибка загрузки'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                ),
              ],
            ),
            child: IconButton(
              onPressed: _deleteImage,
              icon: const Icon(Icons.delete, size: 16, color: Colors.red),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  // Если изображения нет
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
            Icon(Icons.add_photo_alternate, color: Colors.grey, size: 40),
            SizedBox(height: 12),
            Text('Добавить фото'),
          ],
        ),
      ),
    ),
  );
}

  Future<void> _deleteImage() async {
    setState(() {
      _isDeletingImage = true;
    });
  }

  Future<void> _updatePost() async {
    if (_contentController.text.trim().isEmpty && _image == null && _isDeletingImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пост не может быть пустым'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      String? photoUrl = widget.post['photo_url'];
      
      // Если выбрано новое изображение
      if (_image != null) {
        String fileName = '${DateTime.now().millisecondsSinceEpoch}_${_image!.name}';
        
        if (kIsWeb) {
          if (_imageBytes != null) {
            await SupabaseConfig.client.storage
                .from('car-photos')
                .uploadBinary(fileName, _imageBytes!);
          } else {
            throw Exception('Изображение не загружено');
          }
        } else {
          final file = File(_image!.path);
          await SupabaseConfig.client.storage
              .from('car-photos')
              .upload(fileName, file);
        }

        final newPhotoUrl = SupabaseConfig.client.storage
            .from('car-photos')
            .getPublicUrl(fileName);
            
        photoUrl = newPhotoUrl;
      }
      
      // Если изображение удалено
      if (_isDeletingImage) {
        photoUrl = null;
      }

      // ДОБАВЬТЕ ЭТУ СТРОКУ ДЛЯ ОТЛАДКИ:
      print('Updating post with data: ${{ 'content': _contentController.text.trim(), 'photo_url': photoUrl, }}');

      await SupabaseConfig.client.from('posts').update({
        'content': _contentController.text.trim(),
        'photo_url': photoUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.post['id']);

      widget.onUpdated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Пост обновлен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error updating post: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления поста: ${e.toString()}'),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500,
          maxHeight: 600,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Редактировать пост',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 20),
                
                _buildImagePreview(),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    labelText: 'Описание',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  maxLines: 4,
                  minLines: 3,
                ),
                
                const SizedBox(height: 24),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _updatePost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Сохранить'),
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