class ServiceModel {
  final int id;
  final String name;
  final String type;
  final String description;
  final String address;
  final double latitude;
  final double longitude;
  final double rating;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServiceModel({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    return ServiceModel(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      description: json['description'] ?? '',
      address: json['address'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      rating: (json['rating'] ?? 0).toDouble(),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  String getTypeName() {
    switch (type) {
      case 'detailing':
        return 'Детейлинг';
      case 'wash':
        return 'Мойка';
      case 'tire_service':
        return 'Шиномонтаж';
      default:
        return 'Сервис';
    }
  }
}