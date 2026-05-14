import 'package:flutter/material.dart';

class ServiceFilterSheet extends StatefulWidget {
  final String? selectedType;
  final Function(String? type) onFilterChanged;
  const ServiceFilterSheet({super.key, this.selectedType, required this.onFilterChanged});

  @override
  State<ServiceFilterSheet> createState() => _ServiceFilterSheetState();
}

class _ServiceFilterSheetState extends State<ServiceFilterSheet> {
  final List<Map<String, String>> _types = [
    {'value': 'all', 'label': 'Все'},
    {'value': 'detailing', 'label': 'Детейлинг'},
    {'value': 'wash', 'label': 'Мойка'},
    {'value': 'tire_service', 'label': 'Шиномонтаж'},
  ];
  String _selectedType = 'all';

  @override
  void initState() {
    super.initState();
    _selectedType = widget.selectedType ?? 'all';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Фильтр сервисов', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: _types.map((type) {
              return FilterChip(
                label: Text(
                  type['label']!,
                  style: TextStyle(
                    color: _selectedType == type['value'] ? Colors.white : Colors.black87,
                  ),
                ),
                selected: _selectedType == type['value'],
                selectedColor: Colors.black87,
                checkmarkColor: Colors.white,
                backgroundColor: Colors.grey[200],
                onSelected: (selected) {
                  setState(() {
                    _selectedType = type['value']!;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена', style: TextStyle(color: Colors.black87)),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  final newType = _selectedType == 'all' ? null : _selectedType;
                  widget.onFilterChanged(newType);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Применить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}