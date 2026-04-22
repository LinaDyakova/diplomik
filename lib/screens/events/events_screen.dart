import 'package:flutter/material.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'package:intl/intl.dart';
import 'edit_event_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _filteredEvents = [];
  Set<int> _registeredEvents = {};
  bool _isLoading = true;
  bool _showOnlyRegistered = false;
  String _selectedCategory = 'Все';
  List<String> _categories = ['Все', 'Встречи', 'Гонки', 'Выставки', 'Благотворительность'];

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _loadUserRegistrations();
  }

  Future<void> _loadEvents() async {
    try {
      final response = await SupabaseConfig.client
          .from('events')
          .select('''
            *,
            profiles!events_creator_id_fkey(username, avatar_url)
          ''')
          .order('event_date', ascending: true);

      setState(() {
        _events = List<Map<String, dynamic>>.from(response);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading events: $e');
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
        _registeredEvents = Set.from(
            response.map((reg) => reg['event_id'] as int));
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
      filtered = filtered.where((event) => _registeredEvents.contains(event['id'])).toList();
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
    if (userId == null) return;

    try {
      await SupabaseConfig.client.from('event_registrations').insert({
        'user_id': userId,
        'event_id': eventId,
        'status': 'registered',
      });

      setState(() {
        _registeredEvents.add(eventId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Вы успешно записались на мероприятие!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка записи: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Вы отменили запись на мероприятие'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка отмены записи: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      await SupabaseConfig.client
          .from('events')
          .delete()
          .eq('id', eventId);

      setState(() {
        _events.removeWhere((event) => event['id'] == eventId);
        _applyFilters();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Мероприятие удалено'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка удаления: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
                        selectedColor: Colors.blueAccent,
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
                    activeColor: Colors.blueAccent,
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
                            foregroundColor: Colors.blueAccent,
                            side: const BorderSide(color: Colors.blueAccent),
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
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
    final hasActiveFilters = _showOnlyRegistered || _selectedCategory != 'Все';

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
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.filter_list, color: Colors.blueAccent),
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
            icon: const Icon(Icons.add, color: Colors.blueAccent),
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/add_event');
              if (result == true) {
                await _refreshEvents();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Мероприятие создано!'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Colors.blueAccent,
              ),
            )
          : RefreshIndicator(
              onRefresh: _refreshEvents,
              backgroundColor: Colors.white,
              color: Colors.blueAccent,
              child: Column(
                children: [
                  if (hasActiveFilters)
                    Container(
                      color: Colors.grey[50],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                                Icon(
                                  Icons.event_note,
                                  size: 80,
                                  color: Colors.grey[300],
                                ),
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
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                    ),
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
                                        style: TextStyle(
                                          color: Colors.blueAccent,
                                        ),
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
                              final isCreator = userId == event['creator_id'];
                              final isRegistered = _registeredEvents.contains(event['id']);
                              return _buildEventCard(event, isCreator, isRegistered);
                            },
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
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blueAccent,
        deleteIcon: const Icon(Icons.close, size: 16),
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
    final formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(eventDate);
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    final daysUntilEvent = eventDate.difference(DateTime.now()).inDays;
    final hoursUntilEvent = eventDate.difference(DateTime.now()).inHours;

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16.0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getCategoryIcon(event['category']),
                  color: Colors.blueAccent,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['title'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (event['category'] != null)
                        Text(
                          event['category'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                if (isCreator)
                  IconButton(
                    onPressed: () {
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
                                  leading: const Icon(Icons.edit, color: Colors.blueAccent),
                                  title: const Text('Редактировать'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _editEvent(event);
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete, color: Colors.red),
                                  title: const Text('Удалить', style: TextStyle(color: Colors.red)),
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
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (daysUntilEvent <= 7 && daysUntilEvent >= 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange[100]!),
                        ),
                        child: Text(
                          daysUntilEvent == 0 
                              ? 'Сегодня' 
                              : 'Через $daysUntilEvent дн.',
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                if (event['location'] != null && event['location'].isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event['location'],
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),

                if (event['description'] != null && event['description'].isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Text(
                      event['description'],
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                  ),

                if (event['profiles'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: event['profiles']?['avatar_url'] != null
                              ? NetworkImage(event['profiles']['avatar_url'])
                              : null,
                          child: event['profiles']?['avatar_url'] == null
                              ? Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.grey[400],
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Организатор',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              '@${event['profiles']?['username'] ?? 'Неизвестен'}', 
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: currentUserId == null
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: const Center(
                      child: Text(
                        'Войдите, чтобы записаться',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : isCreator
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(10.0),
                          border: Border.all(color: Colors.blue[100]!),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.star, color: Colors.blueAccent, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Вы организатор',
                                style: TextStyle(
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : isRegistered
                        ? Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(10.0),
                              border: Border.all(color: Colors.green[100]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle,
                                    color: Colors.green, size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'Вы участвуете',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => _unregisterFromEvent(event['id']),
                                  child: const Text(
                                    'Отменить',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ElevatedButton(
                            onPressed: () {
                              _registerForEvent(event['id']);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                            child: const Text(
                              'Записаться',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
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