import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vroom/models/service_model.dart';
import 'package:vroom/screens/map/city_picker_dialog.dart';
import 'package:vroom/screens/map/service_filter_sheet.dart';
import 'package:vroom/supabase/supabase_config.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  LatLng _center = const LatLng(55.751244, 37.618423);
  String _cityName = 'Москва';
  bool _isLoading = true;
  final MapController _mapController = MapController();
  Position? _currentPosition;

  List<ServiceModel> _allServices = [];
  List<ServiceModel> _filteredServices = [];
  String? _selectedServiceType;
  bool _showServices = true;

  List<Map<String, dynamic>> _allEvents = [];
  List<Map<String, dynamic>> _filteredEvents = [];
  bool _showEvents = true;

  List<Map<String, dynamic>> _allFuelStations = [];
  List<Map<String, dynamic>> _filteredFuelStations = [];

  String _searchMode = 'city';
  static const double _nearbyRadiusMeters = 5000;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0) {
          _loadServices();
        } else if (_tabController.index == 1) {
          _loadEvents();
        } else if (_tabController.index == 2) {
          _loadFuelStations();
        }
      }
    });
    _loadUserCity();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showErrorSnackBar('Службы геолокации отключены. Включите GPS.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
          _showErrorSnackBar('Разрешение на геолокацию не получено.');
          return;
        }
      }
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _center = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_center, 12);
      // Загружаем данные после получения локации
      await Future.wait([
        _loadServices(),
        _loadEvents(),
        _loadFuelStations(),
      ]);
      _applyAllFilters();
    } catch (e) {
      _showErrorSnackBar('Ошибка получения местоположения: ${e.toString().substring(0, 100)}');
    }
  }

  Future<void> _loadUserCity() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final response = await SupabaseConfig.client
          .from('profiles')
          .select('city, latitude, longitude')
          .eq('id', userId)
          .maybeSingle(); // используем maybeSingle вместо single, чтобы избежать исключения при отсутствии
      if (response != null && response['latitude'] != null && response['longitude'] != null) {
        setState(() {
          _center = LatLng(response['latitude'], response['longitude']);
          _cityName = response['city'] ?? 'Город';
        });
      } else {
        _showCityPicker();
      }
    } catch (e) {
      _showErrorSnackBar('Не удалось загрузить город пользователя');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showCityPicker() {
    showDialog(
      context: context,
      builder: (context) => CityPickerDialog(
        onCitySelected: (city, lat, lon) {
          _saveCityToProfile(city, lat, lon);
        },
      ),
    );
  }

  Future<void> _saveCityToProfile(String city, double lat, double lon) async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) {
      _showErrorSnackBar('Пользователь не авторизован');
      return;
    }
    try {
      await SupabaseConfig.client.from('profiles').update({
        'city': city,
        'latitude': lat,
        'longitude': lon,
      }).eq('id', userId);
      setState(() {
        _center = LatLng(lat, lon);
        _cityName = city;
      });
      _mapController.move(_center, 10);
      await Future.wait([
        _loadServices(),
        _loadEvents(),
        _loadFuelStations(),
      ]);
      _applyAllFilters();
    } catch (e) {
      _showErrorSnackBar('Ошибка сохранения города: ${e.toString()}');
    }
  }

  Future<void> _loadServices() async {
    try {
      var query = SupabaseConfig.client.from('services').select();
      if (_selectedServiceType != null) {
        query = query.eq('type', _selectedServiceType!);
      }
      final response = await query;
      final List<dynamic> data = response;
      final all = data.map((json) => ServiceModel.fromJson(json)).toList();
      setState(() {
        _allServices = all;
      });
      _applyServiceFilter();
    } catch (e) {
      _showErrorSnackBar('Ошибка загрузки сервисов');
      setState(() => _filteredServices = []);
    }
  }

  void _applyServiceFilter() {
    List<ServiceModel> filtered = List.from(_allServices);
    if (_selectedServiceType != null) {
      filtered = filtered.where((s) => s.type == _selectedServiceType).toList();
    }
    if (_searchMode == 'nearby' && _currentPosition != null) {
      final userLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      filtered = filtered.where((s) {
        final serviceLatLng = LatLng(s.latitude, s.longitude);
        return _calculateDistance(userLatLng, serviceLatLng) <= _nearbyRadiusMeters;
      }).toList();
    }
    setState(() {
      _filteredServices = filtered;
    });
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const double R = 6371000;
    final dLat = _toRadians(p2.latitude - p1.latitude);
    final dLon = _toRadians(p2.longitude - p1.longitude);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(p1.latitude)) * cos(_toRadians(p2.latitude)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) => degrees * (pi / 180);

  Future<void> _loadEvents() async {
    try {
      final response = await SupabaseConfig.client
          .from('events')
          .select()
          .gte('event_date', DateTime.now().toIso8601String());
      final List<dynamic> data = response;
      setState(() {
        _allEvents = data.cast<Map<String, dynamic>>();
      });
      _applyEventFilter();
    } catch (e) {
      _showErrorSnackBar('Ошибка загрузки мероприятий');
      setState(() => _filteredEvents = []);
    }
  }

  void _applyEventFilter() {
    List<Map<String, dynamic>> filtered = List.from(_allEvents);
    if (_searchMode == 'nearby' && _currentPosition != null) {
      final userLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      filtered = filtered.where((event) {
        if (event['latitude'] == null || event['longitude'] == null) return false;
        final eventLatLng = LatLng(event['latitude'], event['longitude']);
        return _calculateDistance(userLatLng, eventLatLng) <= _nearbyRadiusMeters;
      }).toList();
    }
    setState(() {
      _filteredEvents = filtered;
    });
  }

  Future<void> _loadFuelStations() async {
    try {
      final response = await SupabaseConfig.client.from('fuel_stations').select();
      setState(() {
        _allFuelStations = List<Map<String, dynamic>>.from(response);
      });
      _applyFuelStationFilter();
    } catch (e) {
      _showErrorSnackBar('Ошибка загрузки АЗС');
      setState(() => _filteredFuelStations = []);
    }
  }

  void _applyFuelStationFilter() {
    List<Map<String, dynamic>> filtered = List.from(_allFuelStations);
    if (_searchMode == 'nearby' && _currentPosition != null) {
      final userLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      filtered = filtered.where((station) {
        final stationLatLng = LatLng(station['latitude'], station['longitude']);
        return _calculateDistance(userLatLng, stationLatLng) <= _nearbyRadiusMeters;
      }).toList();
    }
    setState(() {
      _filteredFuelStations = filtered;
    });
  }

  void _applyAllFilters() {
    _applyServiceFilter();
    _applyEventFilter();
    _applyFuelStationFilter();
  }

  void _centerOnUser() async {
    if (_currentPosition != null) {
      try {
        _mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 14);
        // Опционально перезагружаем данные
        await Future.wait([
          _loadServices(),
          _loadEvents(),
          _loadFuelStations(),
        ]);
        _applyAllFilters();
      } catch (e) {
        _showErrorSnackBar('Ошибка при центрировании карты');
      }
    } else {
      _showErrorSnackBar('Не удалось определить местоположение');
    }
  }

  void _showServiceFilter() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ServiceFilterSheet(
        selectedType: _selectedServiceType,
        onFilterChanged: (type) {
          setState(() {
            _selectedServiceType = type;
          });
          _loadServices();
        },
      ),
    );
  }

  void _toggleSearchMode() {
    setState(() {
      _searchMode = _searchMode == 'city' ? 'nearby' : 'city';
    });
    _applyAllFilters();
    if (_searchMode == 'nearby' && _currentPosition == null) {
      _showErrorSnackBar('Включите геолокацию для поиска рядом со мной');
    }
  }

  Future<void> _openExternalNavigation(LatLng destination) async {
    final naviUrl = 'yandexnavi://build_route_on_map?lat_to=${destination.latitude}&lon_to=${destination.longitude}';
    final mapsUrl = 'yandexmaps://maps.yandex.ru/?pt=${destination.longitude},${destination.latitude}&z=15';
    final webUrl = 'https://yandex.ru/maps/?pt=${destination.longitude},${destination.latitude}&z=15';

    try {
      if (await canLaunchUrl(Uri.parse(naviUrl))) {
        await launchUrl(Uri.parse(naviUrl));
        return;
      }
      if (await canLaunchUrl(Uri.parse(mapsUrl))) {
        await launchUrl(Uri.parse(mapsUrl));
        return;
      }
      if (await canLaunchUrl(Uri.parse(webUrl))) {
        await launchUrl(Uri.parse(webUrl));
        return;
      }
      throw 'Не удалось открыть карту';
    } catch (e) {
      _showErrorSnackBar('Ошибка открытия навигации');
    }
  }

  IconData _getEventIcon(String? category) {
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

  Future<void> _updateServiceAverageRating(int serviceId) async {
    try {
      final avgRes = await SupabaseConfig.client
          .from('service_reviews')
          .select('rating')
          .eq('service_id', serviceId);
      if (avgRes.isEmpty) return;
      double sum = 0;
      for (var r in avgRes) {
        sum += r['rating'] as int;
      }
      double avg = sum / avgRes.length;
      await SupabaseConfig.client
          .from('services')
          .update({'rating': avg})
          .eq('id', serviceId);
    } catch (e) {
      // Ошибка при пересчёте рейтинга не должна прерывать пользовательский опыт
      print('Rating update error: $e');
    }
  }

  void _showServiceDetails(ServiceModel service) {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) {
      _showUnauthenticatedServiceDetails(service);
      return;
    }

    Future<int?> getUserRating() async {
      try {
        final res = await SupabaseConfig.client
            .from('service_reviews')
            .select('rating')
            .eq('service_id', service.id)
            .eq('user_id', currentUserId)
            .maybeSingle();
        return res?['rating'] as int?;
      } catch (e) {
        return null;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FutureBuilder<int?>(
        future: getUserRating(),
        builder: (context, snapshot) {
          int? userRating = snapshot.data;
          bool hasRated = userRating != null;
          int selectedRating = userRating ?? 0;
          return StatefulBuilder(
            builder: (context, setStateModal) {
              bool isSubmitting = false;
              return Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 8),
                    if (service.address.isNotEmpty)
                      Text('📍 ${service.address}', style: const TextStyle(color: Colors.black87)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 4),
                        Text(service.rating.toStringAsFixed(1)),
                        const SizedBox(width: 16),
                        const Text('Ваша оценка:', style: TextStyle(color: Colors.black87)),
                        ...List.generate(5, (i) {
                          final starIcon = Icon(
                            i < selectedRating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 24,
                          );
                          if (hasRated) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: starIcon,
                            );
                          } else {
                            return GestureDetector(
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      setStateModal(() => selectedRating = i + 1);
                                      setStateModal(() => isSubmitting = true);
                                      try {
                                        final existing = await SupabaseConfig.client
                                            .from('service_reviews')
                                            .select('id')
                                            .eq('service_id', service.id)
                                            .eq('user_id', currentUserId)
                                            .maybeSingle();
                                        if (existing != null) {
                                          await SupabaseConfig.client
                                              .from('service_reviews')
                                              .update({'rating': i + 1})
                                              .eq('id', existing['id']);
                                        } else {
                                          await SupabaseConfig.client
                                              .from('service_reviews')
                                              .insert({
                                            'service_id': service.id,
                                            'user_id': currentUserId,
                                            'rating': i + 1,
                                          });
                                        }
                                        await _updateServiceAverageRating(service.id);

                                        final updatedData = await SupabaseConfig.client
                                            .from('services')
                                            .select()
                                            .eq('id', service.id)
                                            .single();
                                        final updatedService = ServiceModel.fromJson(updatedData);

                                        setState(() {
                                          final index = _allServices.indexWhere((s) => s.id == service.id);
                                          if (index != -1) {
                                            _allServices[index] = updatedService;
                                          }
                                          _applyServiceFilter();
                                        });

                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Спасибо за оценку!'), backgroundColor: Colors.green),
                                          );
                                          Navigator.pop(context);
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Ошибка при оценке: ${e.toString().substring(0, 100)}'), backgroundColor: Colors.red),
                                          );
                                        }
                                        setStateModal(() => isSubmitting = false);
                                      }
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: starIcon,
                              ),
                            );
                          }
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _openExternalNavigation(LatLng(service.latitude, service.longitude));
                          },
                          icon: const Icon(Icons.directions, size: 18),
                          label: const Text('Маршрут'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showUnauthenticatedServiceDetails(ServiceModel service) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(service.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 8),
            if (service.address.isNotEmpty)
              Text('📍 ${service.address}', style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text(service.rating.toStringAsFixed(1)),
                const SizedBox(width: 16),
                const Text('Войдите, чтобы оценить', style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openExternalNavigation(LatLng(service.latitude, service.longitude));
                  },
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text('Маршрут'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateFuelStationAverageRating(int stationId) async {
    try {
      final avgRes = await SupabaseConfig.client
          .from('fuel_station_reviews')
          .select('rating')
          .eq('fuel_station_id', stationId);
      if (avgRes.isEmpty) return;
      double sum = 0;
      for (var r in avgRes) {
        sum += r['rating'] as int;
      }
      double avg = sum / avgRes.length;
      await SupabaseConfig.client
          .from('fuel_stations')
          .update({'rating': avg})
          .eq('id', stationId);
    } catch (e) {
      print('Rating update error: $e');
    }
  }

  void _showFuelStationDetails(Map<String, dynamic> station) {
    final currentUserId = SupabaseConfig.auth.currentUser?.id;
    if (currentUserId == null) {
      _showUnauthenticatedFuelStationDetails(station);
      return;
    }

    Future<int?> getUserRating() async {
      try {
        final res = await SupabaseConfig.client
            .from('fuel_station_reviews')
            .select('rating')
            .eq('fuel_station_id', station['id'])
            .eq('user_id', currentUserId)
            .maybeSingle();
        return res?['rating'] as int?;
      } catch (e) {
        return null;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FutureBuilder<int?>(
        future: getUserRating(),
        builder: (context, snapshot) {
          int? userRating = snapshot.data;
          bool hasRated = userRating != null;
          int selectedRating = userRating ?? 0;
          return StatefulBuilder(
            builder: (context, setStateModal) {
              bool isSubmitting = false;
              return Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(station['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 8),
                    if (station['address'] != null)
                      Text('📍 ${station['address']}', style: const TextStyle(color: Colors.black87)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 4),
                        Text((station['rating'] ?? 0.0).toStringAsFixed(1)),
                        const SizedBox(width: 16),
                        const Text('Ваша оценка:', style: TextStyle(color: Colors.black87)),
                        ...List.generate(5, (i) {
                          final starIcon = Icon(
                            i < selectedRating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 24,
                          );
                          if (hasRated) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: starIcon,
                            );
                          } else {
                            return GestureDetector(
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      setStateModal(() => selectedRating = i + 1);
                                      setStateModal(() => isSubmitting = true);
                                      try {
                                        final existing = await SupabaseConfig.client
                                            .from('fuel_station_reviews')
                                            .select('id')
                                            .eq('fuel_station_id', station['id'])
                                            .eq('user_id', currentUserId)
                                            .maybeSingle();
                                        if (existing != null) {
                                          await SupabaseConfig.client
                                              .from('fuel_station_reviews')
                                              .update({'rating': i + 1})
                                              .eq('id', existing['id']);
                                        } else {
                                          await SupabaseConfig.client
                                              .from('fuel_station_reviews')
                                              .insert({
                                            'fuel_station_id': station['id'],
                                            'user_id': currentUserId,
                                            'rating': i + 1,
                                          });
                                        }
                                        await _updateFuelStationAverageRating(station['id']);

                                        final updatedData = await SupabaseConfig.client
                                            .from('fuel_stations')
                                            .select()
                                            .eq('id', station['id'])
                                            .single();

                                        setState(() {
                                          final index = _allFuelStations.indexWhere((s) => s['id'] == station['id']);
                                          if (index != -1) {
                                            _allFuelStations[index] = updatedData;
                                          }
                                          _applyFuelStationFilter();
                                        });

                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Спасибо за оценку!'), backgroundColor: Colors.green),
                                          );
                                          Navigator.pop(context);
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Ошибка: ${e.toString().substring(0, 100)}'), backgroundColor: Colors.red),
                                          );
                                        }
                                        setStateModal(() => isSubmitting = false);
                                      }
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: starIcon,
                              ),
                            );
                          }
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _openExternalNavigation(LatLng(station['latitude'], station['longitude']));
                          },
                          icon: const Icon(Icons.directions, size: 18),
                          label: const Text('Маршрут'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showUnauthenticatedFuelStationDetails(Map<String, dynamic> station) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(station['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 8),
            if (station['address'] != null)
              Text('📍 ${station['address']}', style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text((station['rating'] ?? 0.0).toStringAsFixed(1)),
                const SizedBox(width: 16),
                const Text('Войдите, чтобы оценить', style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openExternalNavigation(LatLng(station['latitude'], station['longitude']));
                  },
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text('Маршрут'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEventDetails(Map<String, dynamic> event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 8),
              if (event['location'] != null && event['location'].isNotEmpty)
                Text('📍 ${event['location']}', style: const TextStyle(color: Colors.black87)),
              const SizedBox(height: 8),
              if (event['description'] != null && event['description'].isNotEmpty)
                Text(
                  event['description'],
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (event['latitude'] != null && event['longitude'] != null)
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _openExternalNavigation(LatLng(event['latitude'], event['longitude']));
                      },
                      icon: const Icon(Icons.directions, size: 18),
                      label: const Text('Маршрут'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text('Карта', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Colors.black87),
            onPressed: _centerOnUser,
            tooltip: 'Моё местоположение',
          ),
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.filter_list, color: Colors.black87),
                if (_selectedServiceType != null)
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
                        style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _showServiceFilter,
            tooltip: 'Фильтр сервисов',
          ),
          IconButton(
            icon: const Icon(Icons.edit_location_alt, color: Colors.black87),
            onPressed: _showCityPicker,
            tooltip: 'Сменить город',
          ),
          IconButton(
            icon: _searchMode == 'city'
                ? const Icon(Icons.location_city, color: Colors.black87)
                : const Icon(Icons.my_location, color: Colors.black87),
            onPressed: _toggleSearchMode,
            tooltip: _searchMode == 'city' ? 'Показать рядом со мной' : 'Показать по городу',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.black87,
          indicatorWeight: 2,
          labelColor: Colors.black87,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [
            Tab(text: 'Сервисы'),
            Tab(text: 'Мероприятия'),
            Tab(text: 'АЗС'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black87))
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: _center,
                zoom: 10,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.vroom',
                ),
                if (_tabController.index == 0 && _showServices)
                  MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      size: const Size(40, 40),
                      markers: _filteredServices.map((service) {
                        return Marker(
                          width: 40,
                          height: 40,
                          point: LatLng(service.latitude, service.longitude),
                          child: GestureDetector(
                            onTap: () => _showServiceDetails(service),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF4A90E2),
                                shape: BoxShape.circle,
                                boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                              ),
                              child: const Icon(Icons.car_repair, color: Colors.white, size: 20),
                            ),
                          ),
                        );
                      }).toList(),
                      builder: (context, markers) {
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A90E2),
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                          ),
                          child: Center(
                            child: Text(
                              markers.length.toString(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (_tabController.index == 1 && _showEvents)
                  MarkerLayer(
                    markers: _filteredEvents.map((event) {
                      if (event['latitude'] == null || event['longitude'] == null) return null;
                      final category = event['category'];
                      return Marker(
                        width: 40,
                        height: 40,
                        point: LatLng(event['latitude'], event['longitude']),
                        child: GestureDetector(
                          onTap: () => _showEventDetails(event),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE25C4A),
                              shape: BoxShape.circle,
                              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                            ),
                            child: Icon(_getEventIcon(category), color: Colors.white, size: 20),
                          ),
                        ),
                      );
                    }).whereType<Marker>().toList(),
                  ),
                if (_tabController.index == 2)
                  MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      size: const Size(40, 40),
                      markers: _filteredFuelStations.map((station) {
                        return Marker(
                          width: 40,
                          height: 40,
                          point: LatLng(station['latitude'], station['longitude']),
                          child: GestureDetector(
                            onTap: () => _showFuelStationDetails(station),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF2ECC71),
                                shape: BoxShape.circle,
                                boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                              ),
                              child: const Icon(Icons.local_gas_station, color: Colors.white, size: 20),
                            ),
                          ),
                        );
                      }).toList(),
                      builder: (context, markers) {
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2ECC71),
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                          ),
                          child: Center(
                            child: Text(
                              markers.length.toString(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (_currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 40,
                        height: 40,
                        point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                          ),
                          child: const Icon(Icons.my_location, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}