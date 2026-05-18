import 'package:flutter/material.dart';
import 'package:vroom/services/geocoding_service.dart';
import 'dart:async';

class CityPickerDialog extends StatefulWidget {
  final Function(String city, double lat, double lon) onCitySelected;

  const CityPickerDialog({super.key, required this.onCitySelected});

  @override
  State<CityPickerDialog> createState() => _CityPickerDialogState();
}

class _CityPickerDialogState extends State<CityPickerDialog> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _errorText;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onSearchChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchCity(_controller.text.trim());
    });
  }

  Future<void> _searchCity(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults.clear();
        _isSearching = false;
        _errorText = null;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _errorText = null;
    });
    try {
      final result = await GeocodingService.geocodeCity(query);
      if (result != null) {
        setState(() {
          _searchResults = [result];
          _isSearching = false;
        });
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          _errorText = 'Город не найден. Проверьте название.';
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _errorText = 'Ошибка поиска. Проверьте интернет.';
      });
    }
  }

  void _selectCity(Map<String, dynamic> city) {
    widget.onCitySelected(
      city['city'] ?? city['displayName'].split(',').first,
      city['lat'],
      city['lon'],
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Выберите ваш город',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Введите название города',
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[100],
                errorText: _errorText,
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
                  borderSide: const BorderSide(color: Colors.black87, width: 1.5),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Colors.black87),
                  onPressed: () => _searchCity(_controller.text.trim()),
                ),
              ),
              onSubmitted: (_) => _searchCity(_controller.text.trim()),
            ),
            const SizedBox(height: 16),
            if (_isSearching)
              const Center(child: CircularProgressIndicator(color: Colors.black87))
            else if (_searchResults.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final city = _searchResults[index];
                    final cityName = city['city'] ?? city['displayName'].split(',').first;
                    return ListTile(
                      title: Text(cityName, style: const TextStyle(color: Colors.black87)),
                      onTap: () => _selectCity(city),
                    );
                  },
                ),
              )
            else if (_controller.text.isNotEmpty && !_isSearching && _errorText == null)
              const Text(
                'Город не найден',
                style: TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}