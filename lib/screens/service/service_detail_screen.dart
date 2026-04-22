import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vroom/models/service_model.dart';
import 'package:vroom/models/service_review_model.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'package:latlong2/latlong.dart';

class ServiceDetailScreen extends StatefulWidget {
  final ServiceModel service;

  const ServiceDetailScreen({super.key, required this.service});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  List<ServiceReviewModel> _reviews = [];
  bool _isLoading = true;
  final TextEditingController _reviewController = TextEditingController();
  int _selectedRating = 5;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final response = await SupabaseConfig.client
          .from('service_reviews')
          .select()
          .eq('service_id', widget.service.id)
          .order('created_at', ascending: false);
      setState(() {
        _reviews = response.map((json) => ServiceReviewModel.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading reviews: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitReview() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы оставить отзыв')),
      );
      return;
    }
    if (_reviewController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Напишите комментарий')),
      );
      return;
    }
    try {
      await SupabaseConfig.client.from('service_reviews').insert({
        'service_id': widget.service.id,
        'user_id': userId,
        'rating': _selectedRating,
        'comment': _reviewController.text.trim(),
      });
      final allReviews = await SupabaseConfig.client
          .from('service_reviews')
          .select('rating')
          .eq('service_id', widget.service.id);
      double avgRating = 0;
      if (allReviews.isNotEmpty) {
        avgRating = allReviews.map((r) => r['rating'] as int).reduce((a, b) => a + b) / allReviews.length;
      }
      await SupabaseConfig.client
          .from('services')
          .update({'rating': avgRating})
          .eq('id', widget.service.id);
      setState(() {
        _reviewController.clear();
        _selectedRating = 5;
      });
      await _loadReviews();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Отзыв добавлен'), backgroundColor: Colors.green),
      );
    } catch (e) {
      print('Error submitting review: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _openExternalNavigation() async {
    final naviUrl = 'yandexnavi://build_route_on_map?lat_to=${widget.service.latitude}&lon_to=${widget.service.longitude}';
    if (await canLaunchUrl(Uri.parse(naviUrl))) {
      await launchUrl(Uri.parse(naviUrl));
      return;
    }
    final mapsUrl = 'yandexmaps://maps.yandex.ru/?pt=${widget.service.longitude},${widget.service.latitude}&z=15';
    if (await canLaunchUrl(Uri.parse(mapsUrl))) {
      await launchUrl(Uri.parse(mapsUrl));
      return;
    }
    final webUrl = 'https://yandex.ru/maps/?pt=${widget.service.longitude},${widget.service.latitude}&z=15';
    await launchUrl(Uri.parse(webUrl));
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays} дн назад';
    if (diff.inHours > 0) return '${diff.inHours} ч назад';
    if (diff.inMinutes > 0) return '${diff.inMinutes} мин назад';
    return 'Только что';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.service.name),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(widget.service.getTypeName()),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 20),
                            const SizedBox(width: 4),
                            Text(widget.service.rating.toStringAsFixed(1)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(widget.service.description, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(child: Text(widget.service.address)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _openExternalNavigation,
                      icon: const Icon(Icons.directions),
                      label: const Text('Построить маршрут'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Оставить отзыв', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Оценка: '),
                DropdownButton<int>(
                  value: _selectedRating,
                  items: [1, 2, 3, 4, 5].map((r) {
                    return DropdownMenuItem(value: r, child: Text(r.toString()));
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedRating = value!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reviewController,
              decoration: InputDecoration(
                hintText: 'Ваш комментарий...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _submitReview,
              child: const Text('Отправить'),
            ),
            const SizedBox(height: 20),
            const Text('Отзывы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_reviews.isEmpty)
              const Text('Пока нет отзывов. Будьте первым!', style: TextStyle(color: Colors.grey))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _reviews.length,
                itemBuilder: (context, index) {
                  final review = _reviews[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Row(
                                children: List.generate(5, (i) => Icon(
                                  i < review.rating ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  size: 16,
                                )),
                              ),
                              const Spacer(),
                              Text(_formatDate(review.createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(review.comment),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}