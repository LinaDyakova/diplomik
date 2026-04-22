import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingService {
  static const String _nominatimUrl = 'https://nominatim.openstreetmap.org/search';

  static Future<List<Map<String, dynamic>>> searchAddress(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await http.get(
        Uri.parse('$_nominatimUrl?q=$query&format=json&addressdetails=1&limit=10'),
        headers: {'User-Agent': 'VroomApp/1.0 (your-email@example.com)'},
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final List<Map<String, dynamic>> results = [];

        for (var item in data) {
          final address = item['address'] ?? {};
          final type = item['type'];

          if (type == 'city' || type == 'town' || type == 'state' || type == 'country') {
            continue;
          }

          final isStreet = address['road'] != null ||
              address['street'] != null ||
              address['pedestrian'] != null;

          if (isStreet) {
            results.add({
              'displayName': item['display_name'],
              'lat': double.parse(item['lat']),
              'lon': double.parse(item['lon']),
            });
          }
        }
        return results;
      } else {
        print('Geocoding error: status code ${response.statusCode}');
      }
    } catch (e) {
      print('Geocoding exception: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> geocodeCity(String cityName) async {
    try {
      final response = await http.get(
        Uri.parse('$_nominatimUrl?q=$cityName&format=json&addressdetails=1&limit=5'),
        headers: {'User-Agent': 'VroomApp/1.0 (dyakova9227@mail.ru)'},
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          Map<String, dynamic>? bestMatch;
          for (var item in data) {
            final type = item['type'];
            if (type == 'city' || type == 'town') {
              bestMatch = item;
              break;
            }
          }
          final selected = bestMatch ?? data.first;
          final address = selected['address'] ?? {};
          String shortCity = address['city'] ??
              address['town'] ??
              address['village'] ??
              address['hamlet'] ??
              address['suburb'] ??
              address['municipality'] ??
              '';
          if (shortCity.isEmpty) {
            final displayName = selected['display_name'] ?? '';
            shortCity = displayName.split(',').first.trim();
          }
          return {
            'lat': double.parse(selected['lat']),
            'lon': double.parse(selected['lon']),
            'city': shortCity,
            'displayName': selected['display_name'],
          };
        }
      } else {
        print('Geocoding error: status code ${response.statusCode}');
      }
    } catch (e) {
      print('Geocoding exception: $e');
    }
    return null;
  }
}