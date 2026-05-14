import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'package:vroom/services/geocoding_service.dart';

class AddEventScreen extends StatefulWidget {
  const AddEventScreen({Key? key}) : super(key: key);

  @override
  _AddEventScreenState createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
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

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }

  // Универсальный метод для показа ошибок
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _geocodeAddress() async {
    final address = _locationController.text.trim();
    if (address.isEmpty) {
      _latitude = null;
      _longitude = null;
      return true;
    }

    try {
      final result = await GeocodingService.geocodeCity(address);
      if (result != null) {
        _latitude = result['lat'];
        _longitude = result['lon'];
        return true;
      } else {
        _showError(
            'Не удалось определить координаты. Проверьте правильность адреса.');
        return false;
      }
    } catch (e) {
      print('Geocoding error: $e');
      _showError(
          'Ошибка геокодирования. Проверьте подключение к интернету или попробуйте позже.');
      return false;
    }
  }

  Future<void> _addEvent() async {
    // Проверка авторизации
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      _showError('Войдите, чтобы создать мероприятие');
      return;
    }

    // Проверка обязательных полей
    final missingFields = <String>[];
    if (_titleController.text.trim().isEmpty) missingFields.add('название');
    if (_selectedDate == null) missingFields.add('дату');
    if (_selectedTime == null) missingFields.add('время');
    if (_locationController.text.trim().isEmpty) missingFields.add('место проведения');

    if (missingFields.isNotEmpty) {
      final fieldsText = missingFields.join(', ');
      _showError('Заполните обязательные поля: $fieldsText');
      return;
    }

    // Проверка формата адреса
    final address = _locationController.text.trim();
    if (!address.contains(',') && !address.contains(' ')) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Адрес может быть неточным'),
          content: const Text(
            'Рекомендуется указывать адрес в формате "Город, улица, дом".\n'
            'Хотите продолжить с текущим значением?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Исправить'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    // Проверка числового поля
    int? maxParticipants;
    if (_maxParticipantsController.text.trim().isNotEmpty) {
      try {
        maxParticipants = int.parse(_maxParticipantsController.text.trim());
      } catch (_) {
        _showError('Введите корректное число в поле "Макс. участников"');
        return;
      }
    }

    // Валидация даты (на всякий случай, хотя DatePicker ограничивает)
    if (_selectedDate != null && _selectedDate!.isBefore(DateTime.now())) {
      _showError('Дата мероприятия не может быть в прошлом');
      return;
    }

    setState(() => _isLoading = true);

    // Геокодирование
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

      await SupabaseConfig.client.from('events').insert({
        'creator_id': userId,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'event_date': eventDate.toIso8601String(),
        'location': address,
        'category': _selectedCategory,
        'max_participants': maxParticipants,
        'latitude': _latitude,
        'longitude': _longitude,
      });

      if (!mounted) return;
      _showSuccess('Мероприятие успешно создано!');
      Navigator.pop(context, true);
    } catch (e) {
      print('Error adding event: $e');
      _showError('Не удалось создать мероприятие. Попробуйте позже.');
      // Даём возможность повторить, не сбрасывая форму
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate() async {
    try {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime(2030),
      );
      if (date != null) {
        setState(() => _selectedDate = date);
      }
    } catch (e) {
      print('Date picker error: $e');
      _showError('Не удалось открыть выбор даты');
    }
  }

  Future<void> _selectTime() async {
    try {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() => _selectedTime = time);
      }
    } catch (e) {
      print('Time picker error: $e');
      _showError('Не удалось открыть выбор времени');
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
          'Создать мероприятие',
          style: TextStyle(color: Colors.black87),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildTextField(_titleController, 'Название мероприятия (обязательное поле)'),
            const SizedBox(height: 16),
            _buildTextField(
              _descriptionController,
              'Описание',
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: _inputDecoration('Категория'),
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
                  child: _dateTimeButton(
                    onPressed: _selectDate,
                    text: _selectedDate == null
                        ? 'Выбрать дату (обязательное поле)'
                        : DateFormat('dd.MM.yyyy').format(_selectedDate!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _dateTimeButton(
                    onPressed: _selectTime,
                    text: _selectedTime == null
                        ? 'Выбрать время (обязательное поле)'
                        : _selectedTime!.format(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              decoration: _inputDecoration(
                'Место проведения (обязательное поле)',
                hintText: 'Например: Москва, ул. Тверская, 1',
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              _maxParticipantsController,
              'Макс. участников (оставьте пустым для неограниченного)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(
                  child: CircularProgressIndicator(color: Colors.black87))
            else
              ElevatedButton(
                onPressed: _addEvent,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Создать мероприятие',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      {int maxLines = 1, TextInputType? keyboardType, String? hintText}) {
    return TextField(
      controller: controller,
      decoration: _inputDecoration(label, hintText: hintText),
      maxLines: maxLines,
      keyboardType: keyboardType,
    );
  }

  InputDecoration _inputDecoration(String label, {String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: const TextStyle(color: Colors.grey),
      hintStyle: TextStyle(color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _dateTimeButton({required VoidCallback onPressed, required String text}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[100],
        foregroundColor: Colors.black87,
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey[300]!),
        ),
        elevation: 0,
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}