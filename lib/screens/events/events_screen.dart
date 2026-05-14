import 'package:flutter/material.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'package:intl/intl.dart';
import 'edit_event_screen.dart';
import 'package:vroom/screens/events/event_detail_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _filteredEvents = [];
  Set<int> _registeredEvents = {};
  Map<int, int> _participantsCounts = {};
  bool _isLoading = true;
  bool _showOnlyRegistered = false;
  String _selectedCategory = 'Все';
  String? _error; // Сообщение об ошибке загрузки

  List<String> _categories = [
    'Все',
    'Встречи',
    'Гонки',
    'Выставки',
    'Благотворительность'
  ];

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _loadUserRegistrations();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await SupabaseConfig.client
          .from('events')
          .select('''
            *,
            profiles!events_creator_id_fkey(username, avatar_url)
          ''')
          .order('event_date', ascending: true);

      final events = List<Map<String, dynamic>>.from(response);
      setState(() {
        _events = events;
      });

      await _loadParticipantsCounts();
      _applyFilters();
      setState(() => _isLoading = false);
    } catch (e) {
      print('Error loading events: $e');
      setState(() {
        _isLoading = false;
        _error = 'Не удалось загрузить мероприятия. Проверьте подключение и попробуйте снова.';
      });
    }
  }

  Future<void> _loadParticipantsCounts() async {
    if (_events.isEmpty) return;
    final eventIds = _events.map((e) => e['id'] as int).toList();
    try {
      final response = await SupabaseConfig.client
          .from('event_registrations')
          .select('event_id')
          .eq('status', 'registered')
          .inFilter('event_id', eventIds);

      final counts = <int, int>{};
      for (final row in response) {
        final eid = row['event_id'] as int;
        counts[eid] = (counts[eid] ?? 0) + 1;
      }
      _participantsCounts = counts;
    } catch (e) {
      print('Error loading participants counts: $e');
      _participantsCounts = {};
    }
  }

  Future<void> _loadUserRegistrations() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await SupabaseConfig.client
          .from('event_registrations')
          .select('event_id')
          .eq('user_id', userId)
          .eq('status', 'registered');

      setState(() {
        _registeredEvents =
            Set.from(response.map((reg) => reg['event_id'] as int));
      });
    } catch (e) {
      print('Error loading user registrations: $e');
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_events);

    final now = DateTime.now();
    filtered = filtered.where((event) {
      final eventDate = DateTime.parse(event['event_date']);
      return eventDate.isAfter(now) || eventDate.isAtSameMomentAs(now);
    }).toList();

    if (_showOnlyRegistered) {
      filtered = filtered
          .where((event) => _registeredEvents.contains(event['id']))
          .toList();
    }

    if (_selectedCategory != 'Все') {
      filtered = filtered.where((event) {
        final category = event['category'] ?? '';
        return category == _selectedCategory;
      }).toList();
    }

    setState(() {
      _filteredEvents = filtered;
    });
  }

  Future<void> _refreshEvents() async {
    await _loadEvents();
    await _loadUserRegistrations();
  }

  Future<void> _registerForEvent(int eventId) async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      _showErrorSnackBar('Войдите, чтобы записаться на мероприятие');
      return;
    }

    try {
      await SupabaseConfig.client.from('event_registrations').insert({
        'user_id': userId,
        'event_id': eventId,
        'status': 'registered',
      });

      setState(() {
        _registeredEvents.add(eventId);
        _participantsCounts[eventId] =
            (_participantsCounts[eventId] ?? 0) + 1;
      });

      _showSuccessSnackBar('Вы успешно записались на мероприятие!');
    } catch (e) {
      _showErrorSnackBar('Ошибка записи: $e');
    }
  }

  Future<void> _unregisterFromEvent(int eventId) async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await SupabaseConfig.client
          .from('event_registrations')
          .delete()
          .eq('user_id', userId)
          .eq('event_id', eventId);

      setState(() {
        _registeredEvents.remove(eventId);
        if (_participantsCounts.containsKey(eventId)) {
          _participantsCounts[eventId] =
              (_participantsCounts[eventId]! - 1).clamp(0, 999999);
        }
      });

      _showSuccessSnackBar('Вы отменили запись на мероприятие');
    } catch (e) {
      _showErrorSnackBar('Ошибка отмены записи: $e');
    }
  }

  void _editEvent(Map<String, dynamic> event) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditEventScreen(event: event),
      ),
    );
    if (result == true) {
      await _refreshEvents();
    }
  }

  Future<void> _deleteEvent(int eventId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить мероприятие?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupabaseConfig.client.from('events').delete().eq('id', eventId);

      setState(() {
        _events.removeWhere((event) => event['id'] == eventId);
        _applyFilters();
      });

      _showSuccessSnackBar('Мероприятие удалено');
    } catch (e) {
      _showErrorSnackBar('Ошибка удаления: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Фильтры',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Категория',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categories.map((category) {
                      return FilterChip(
                        label: Text(
                          category,
                          style: TextStyle(
                            color: _selectedCategory == category
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                        selected: _selectedCategory == category,
                        selectedColor: Colors.black87,
                        checkmarkColor: Colors.white,
                        backgroundColor: Colors.grey[200],
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = category;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text(
                      'Только записанные',
                      style: TextStyle(color: Colors.black87),
                    ),
                    value: _showOnlyRegistered,
                    activeColor: Colors.black87,
                    onChanged: (value) {
                      setState(() {
                        _showOnlyRegistered = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _showOnlyRegistered = false;
                              _selectedCategory = 'Все';
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Colors.black87),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Сбросить'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _applyFilters();
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                          ),
                          child: const Text('Применить'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = SupabaseConfig.auth.currentUser?.id;
    final hasActiveFilters =
        _showOnlyRegistered || _selectedCategory != 'Все';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Мероприятия',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.filter_list, color: Colors.black87),
                if (hasActiveFilters)
                  Positioned(
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        '!',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black87),
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/add_event');
              if (result == true) {
                await _refreshEvents();
                _showSuccessSnackBar('Мероприятие создано!');
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.black87))
          : _error != null
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: _refreshEvents,
                  backgroundColor: Colors.white,
                  color: Colors.black87,
                  child: Column(
                    children: [
                      if (hasActiveFilters)
                        Container(
                          color: Colors.grey[50],
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                if (_showOnlyRegistered)
                                  _buildFilterChip('Только записанные'),
                                if (_selectedCategory != 'Все')
                                  _buildFilterChip(_selectedCategory),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: _filteredEvents.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.event_note,
                                        size: 80, color: Colors.grey[300]),
                                    const SizedBox(height: 20),
                                    Text(
                                      'Мероприятия не найдены',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 40.0),
                                      child: Text(
                                        hasActiveFilters
                                            ? 'Попробуйте изменить фильтры'
                                            : 'Пока нет мероприятий. Создайте первое!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey[500]),
                                      ),
                                    ),
                                    if (hasActiveFilters)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _showOnlyRegistered = false;
                                              _selectedCategory = 'Все';
                                            });
                                            _applyFilters();
                                          },
                                          child: const Text(
                                            'Сбросить фильтры',
                                            style:
                                                TextStyle(color: Colors.black87),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16.0),
                                itemCount: _filteredEvents.length,
                                itemBuilder: (context, index) {
                                  final event = _filteredEvents[index];
                                  final isCreator =
                                      userId == event['creator_id'];
                                  final isRegistered =
                                      _registeredEvents.contains(event['id']);
                                  return _buildEventCard(
                                      event, isCreator, isRegistered);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 20),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _refreshEvents,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
        backgroundColor: Colors.black87,
        deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white70),
        onDeleted: () {
          if (label == 'Только записанные') {
            _showOnlyRegistered = false;
          } else if (_categories.contains(label)) {
            _selectedCategory = 'Все';
          }
          _applyFilters();
        },
      ),
    );
  }

Widget _buildEventCard(
    Map<String, dynamic> event, bool isCreator, bool isRegistered) {
  final eventDate = DateTime.parse(event['event_date']);
  final formattedDate = DateFormat('dd MMMM yyyy, HH:mm', 'ru').format(eventDate);
  final dayOfMonth = eventDate.day.toString().padLeft(2, '0');
  final monthAbbr = DateFormat('MMM', 'ru').format(eventDate);
  final daysUntilEvent = eventDate.difference(DateTime.now()).inDays;
  final participants = _participantsCounts[event['id']] ?? 0;
  final maxParticipants = event['max_participants'];
  final category = event['category'] ?? 'Другое';
  final categoryColor = _getCategoryColor(category);
  final currentUserId = SupabaseConfig.auth.currentUser?.id;
  final description = event['description'];

  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EventDetailScreen(eventId: event['id']),
        ),
      );
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: categoryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: categoryColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getCategoryIcon(category),
                            color: categoryColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event['title'],
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                category,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isCreator)
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20)),
                                ),
                                builder: (context) {
                                  return SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.edit,
                                              color: Colors.black87),
                                          title: const Text('Редактировать'),
                                          onTap: () {
                                            Navigator.pop(context);
                                            _editEvent(event);
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.delete,
                                              color: Colors.red),
                                          title: const Text('Удалить',
                                              style:
                                                  TextStyle(color: Colors.red)),
                                          onTap: () {
                                            Navigator.pop(context);
                                            _deleteEvent(event['id']);
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.more_vert,
                                  color: Colors.grey, size: 20),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 50,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Text(
                                dayOfMonth,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                monthAbbr,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formattedDate,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (event['location'] != null &&
                                  event['location'].isNotEmpty)
                                Row(
                                  children: [
                                    Icon(Icons.location_on,
                                        size: 14, color: Colors.grey[500]),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        event['location'],
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        if (daysUntilEvent <= 7 && daysUntilEvent >= 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: daysUntilEvent == 0
                                  ? Colors.green[50]
                                  : Colors.orange[50],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: daysUntilEvent == 0
                                    ? Colors.green[200]!
                                    : Colors.orange[200]!,
                              ),
                            ),
                            child: Text(
                              daysUntilEvent == 0
                                  ? 'Сегодня'
                                  : 'Через $daysUntilEvent дн.',
                              style: TextStyle(
                                color: daysUntilEvent == 0
                                    ? Colors.green[700]
                                    : Colors.orange[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (description != null && description.toString().trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Text(
                          description,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Row(
                      children: [
                        Icon(Icons.people, size: 16, color: Colors.grey[500]),
                        const SizedBox(width: 6),
                        if (maxParticipants != null)
                          RichText(
                            text: TextSpan(
                              style: DefaultTextStyle.of(context).style,
                              children: [
                                TextSpan(
                                  text: '$participants',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                                TextSpan(
                                  text: ' из $maxParticipants участников',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Row(
                            children: [
                              Text(
                                '$participants',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'участников',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        const Spacer(),
                        if (event['profiles'] != null) ...[
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.grey[200],
                            backgroundImage:
                                event['profiles']?['avatar_url'] != null
                                    ? NetworkImage(
                                        event['profiles']['avatar_url'])
                                    : null,
                            child: event['profiles']?['avatar_url'] == null
                                ? Icon(Icons.person,
                                    size: 12, color: Colors.grey[400])
                                : null,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '@${event['profiles']?['username'] ?? 'Неизвестен'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    currentUserId == null
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'Войдите, чтобы записаться',
                                style:
                                    TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                            ),
                          )
                        : isCreator
                            ? Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.grey[300]!),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Вы организатор',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              )
                            : isRegistered
                                ? Container(
                                    width: double.infinity,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.green[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: Colors.green[200]!),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.check_circle,
                                            color: Colors.green, size: 18),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            'Вы участвуете',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              _unregisterFromEvent(
                                                  event['id']),
                                          child: const Text(
                                            'Отменить',
                                            style:
                                                TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () =>
                                          _registerForEvent(event['id']),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black87,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'Записаться',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'Встречи':
        return const Color(0xFF4A90E2);
      case 'Гонки':
        return const Color(0xFFE25C4A);
      case 'Выставки':
        return const Color(0xFF9B59B6);
      case 'Благотворительность':
        return const Color(0xFF2ECC71);
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Встречи':
        return Icons.people;
      case 'Гонки':
        return Icons.speed;
      case 'Выставки':
        return Icons.museum;
      case 'Благотворительность':
        return Icons.favorite;
      default:
        return Icons.event;
    }
  }
}