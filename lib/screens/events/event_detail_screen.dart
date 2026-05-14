import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vroom/supabase/supabase_config.dart';

class EventDetailScreen extends StatefulWidget {
  final int eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  Map<String, dynamic>? _event;
  bool _isLoading = true;
  bool _isRegistered = false;
  int _participantsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadEventDetails();
    _checkRegistration();
  }

  Future<void> _loadEventDetails() async {
    try {
      final response = await SupabaseConfig.client
          .from('events')
          .select('*, profiles!events_creator_id_fkey(username, avatar_url)')
          .eq('id', widget.eventId)
          .single();
      setState(() {
        _event = response;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading event details: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkRegistration() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await SupabaseConfig.client
          .from('event_registrations')
          .select()
          .eq('user_id', userId)
          .eq('event_id', widget.eventId)
          .eq('status', 'registered');
      setState(() {
        _isRegistered = response.isNotEmpty;
      });
      await _loadParticipantsCount();
    } catch (e) {
      print('Error checking registration: $e');
    }
  }

  Future<void> _loadParticipantsCount() async {
    try {
      final response = await SupabaseConfig.client
          .from('event_registrations')
          .select('id')
          .eq('event_id', widget.eventId)
          .eq('status', 'registered');
      setState(() {
        _participantsCount = response.length;
      });
    } catch (e) {
      print('Error loading participants count: $e');
    }
  }

  Future<void> _registerForEvent() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы записаться')),
      );
      return;
    }
    try {
      await SupabaseConfig.client.from('event_registrations').insert({
        'user_id': userId,
        'event_id': widget.eventId,
        'status': 'registered',
      });
      setState(() {
        _isRegistered = true;
        _participantsCount++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Вы записались на мероприятие'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _unregisterFromEvent() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await SupabaseConfig.client
          .from('event_registrations')
          .delete()
          .eq('user_id', userId)
          .eq('event_id', widget.eventId);
      setState(() {
        _isRegistered = false;
        _participantsCount--;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Вы отписались от мероприятия'),
            backgroundColor: Colors.orange),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _openExternalNavigation() async {
    if (_event == null) return;
    final lat = _event!['latitude'];
    final lon = _event!['longitude'];
    if (lat == null || lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Координаты мероприятия не указаны')),
      );
      return;
    }
    final naviUrl = 'yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lon';
    if (await canLaunchUrl(Uri.parse(naviUrl))) {
      await launchUrl(Uri.parse(naviUrl));
      return;
    }
    final mapsUrl = 'yandexmaps://maps.yandex.ru/?pt=$lon,$lat&z=15';
    if (await canLaunchUrl(Uri.parse(mapsUrl))) {
      await launchUrl(Uri.parse(mapsUrl));
      return;
    }
    final webUrl = 'https://yandex.ru/maps/?pt=$lon,$lat&z=15';
    await launchUrl(Uri.parse(webUrl));
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMMM yyyy, HH:mm', 'ru').format(date);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Мероприятие')),
        body: const Center(
            child: CircularProgressIndicator(color: Colors.black87)),
      );
    }
    if (_event == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Мероприятие')),
        body: const Center(child: Text('Мероприятие не найдено')),
      );
    }
    final eventDate = DateTime.parse(_event!['event_date']);
    final formattedDate = _formatDate(eventDate);
    final isCreator =
        SupabaseConfig.auth.currentUser?.id == _event!['creator_id'];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(_event!['title'],
            style: const TextStyle(color: Colors.black87)),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _event!['category'] ?? 'Мероприятие',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const Spacer(),
                Text(
                  formattedDate,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_event!['description'] != null &&
                _event!['description'].isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Описание',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 8),
                  Text(_event!['description'],
                      style: const TextStyle(
                          fontSize: 15, color: Colors.black87)),
                  const SizedBox(height: 16),
                ],
              ),
            if (_event!['location'] != null &&
                _event!['location'].isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Место',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_event!['location'],
                              style: const TextStyle(
                                  fontSize: 15, color: Colors.black87))),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Участники',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: 8),
                Text('$_participantsCount чел.',
                    style:
                        const TextStyle(fontSize: 16, color: Colors.black87)),
                const SizedBox(height: 16),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Организатор',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[200],
                      backgroundImage:
                          _event!['profiles']?['avatar_url'] != null
                              ? NetworkImage(_event!['profiles']['avatar_url'])
                              : null,
                      child: _event!['profiles']?['avatar_url'] == null
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '@${_event!['profiles']?['username'] ?? 'Пользователь'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                          fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
            if (!isCreator)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _isRegistered ? _unregisterFromEvent : _registerForEvent,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isRegistered ? Colors.red : Colors.black87,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    _isRegistered ? 'Отменить запись' : 'Записаться',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (_event!['latitude'] != null && _event!['longitude'] != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openExternalNavigation,
                  icon: const Icon(Icons.directions),
                  label: const Text('Построить маршрут'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: const BorderSide(color: Colors.black87),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}