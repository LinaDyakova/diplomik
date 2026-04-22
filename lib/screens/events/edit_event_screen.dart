import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'package:vroom/services/geocoding_service.dart';

class EditEventScreen extends StatefulWidget {
  final Map<String, dynamic> event;

  const EditEventScreen({Key? key, required this.event}) : super(key: key);

  @override
  _EditEventScreenState createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _maxParticipantsController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isLoading = false;
  String? _selectedCategory;
  final List<String> _categories = [
    'Встречи',
    'Гонки',
    'Выставки',
    'Благотворительность',
    'Другое'
  ];

  double? _latitude;
  double? _longitude;
  String _originalAddress = '';

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.event['title'] ?? '';
    _descriptionController.text = widget.event['description'] ?? '';
    _locationController.text = widget.event['location'] ?? '';
    _selectedCategory = widget.event['category'];
    _originalAddress = _locationController.text;

    if (widget.event['latitude'] != null) {
      _latitude = widget.event['latitude'].toDouble();
    }
    if (widget.event['longitude'] != null) {
      _longitude = widget.event['longitude'].toDouble();
    }
    if (widget.event['max_participants'] != null) {
      _maxParticipantsController.text = widget.event['max_participants'].toString();
    }

    final eventDate = DateTime.parse(widget.event['event_date']);
    _selectedDate = eventDate;
    _selectedTime = TimeOfDay.fromDateTime(eventDate);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }

  Future<bool> _geocodeAddress() async {
    final address = _locationController.text.trim();
    if (address.isEmpty) {
      _latitude = null;
      _longitude = null;
      return true; 
    }

    if (address == _originalAddress && (_latitude != null && _longitude != null)) {
      return true;
    }

    try {
      final result = await GeocodingService.geocodeCity(address);
      if (result != null) {
        _latitude = result['lat'];
        _longitude = result['lon'];
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось определить координаты по адресу. Проверьте правильность написания.'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }
    } catch (e) {
      print('Geocoding error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка геокодирования: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Future<void> _updateEvent() async {
    if (_titleController.text.isEmpty || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заполните обязательные поля'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final geocodeSuccess = await _geocodeAddress();
    if (!geocodeSuccess) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      DateTime eventDate = _selectedDate!;
      if (_selectedTime != null) {
        eventDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
      }

      await SupabaseConfig.client.from('events').update({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'event_date': eventDate.toIso8601String(),
        'location': _locationController.text.trim(),
        'category': _selectedCategory,
        'max_participants': _maxParticipantsController.text.isNotEmpty
            ? int.parse(_maxParticipantsController.text)
            : null,
        'latitude': _latitude,
        'longitude': _longitude,
      }).eq('id', widget.event['id']);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Редактировать мероприятие',
          style: TextStyle(color: Colors.black87),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _updateEvent,
            icon: const Icon(Icons.save, color: Colors.blueAccent),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Название мероприятия*',
                labelStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Описание',
                labelStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: InputDecoration(
                labelText: 'Категория',
                labelStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
              items: _categories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedCategory = value),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectDate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[50],
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: Text(
                      _selectedDate == null
                          ? 'Выбрать дату*'
                          : DateFormat('dd.MM.yyyy').format(_selectedDate!),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectTime,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[50],
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: Text(
                      _selectedTime == null
                          ? 'Выбрать время'
                          : _selectedTime!.format(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: 'Место проведения',
                labelStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxParticipantsController,
              decoration: InputDecoration(
                labelText: 'Макс. участников (оставьте пустым для неограниченного)',
                labelStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
            else
              ElevatedButton(
                onPressed: _updateEvent,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Сохранить изменения',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}