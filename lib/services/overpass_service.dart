import 'dart:convert';
import 'package:http/http.dart' as http;

class OverpassService {
  static const String _overpassUrl = 'https://overpass-api.de/api/interpreter';
  static const String _userAgent = 'VroomApp/1.0 (your-email@example.com)'; 

  static Future<List<Map<String, dynamic>>> fetchNearbyServices(
    double lat,
    double lon,
    double radiusKm,
  ) async {
    final radiusMeters = (radiusKm * 1000).toInt();
    final query = '''
      [out:json];
      (
        node["amenity"="car_wash"](around:$radiusMeters,$lat,$lon);
        node["shop"="car_repair"](around:$radiusMeters,$lat,$lon);
        node["shop"="tires"](around:$radiusMeters,$lat,$lon);
        way["amenity"="car_wash"](around:$radiusMeters,$lat,$lon);
        way["shop"="car_repair"](around:$radiusMeters,$lat,$lon);
        way["shop"="tires"](around:$radiusMeters,$lat,$lon);
      );
      out body;
      >;
      out skel qt;
    ''';

    final response = await http.post(
      Uri.parse(_overpassUrl),
      headers: {'User-Agent': _userAgent},
      body: query,
    );

    if (response.statusCode != 200) {
      throw Exception('Overpass API error: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    final elements = data['elements'] as List;

    final List<Map<String, dynamic>> services = [];

    for (var elem in elements) {
      double? latElem, lonElem;
      if (elem['type'] == 'node') {
        latElem = elem['lat'];
        lonElem = elem['lon'];
      } else if (elem['type'] == 'way') {
        continue;
      } else {
        continue;
      }

      if (latElem == null || lonElem == null) continue;

      String? type;
      if (elem['tags']?['amenity'] == 'car_wash') type = 'wash';
      else if (elem['tags']?['shop'] == 'car_repair') type = 'detailing';
      else if (elem['tags']?['shop'] == 'tires') type = 'tire_service';
      else continue;

      final name = elem['tags']?['name'] ?? 'Без названия';

      String address = '';
      final tags = elem['tags'] ?? {};
      if (tags['addr:street'] != null) {
        address = tags['addr:street'];
        if (tags['addr:housenumber'] != null) {
          address += ', ${tags['addr:housenumber']}';
        }
      } else if (tags['addr:full'] != null) {
        address = tags['addr:full'];
      } else {
        address = 'Адрес не указан';
      }

      services.add({
        'name': name,
        'type': type,
        'description': '', 
        'address': address,
        'latitude': latElem,
        'longitude': lonElem,
        'rating': 0.0,
      });
    }

    final unique = <String, Map<String, dynamic>>{};
    for (var s in services) {
      final key = '${s['latitude']},${s['longitude']}';
      if (!unique.containsKey(key)) {
        unique[key] = s;
      }
    }

    return unique.values.toList();
  }
}