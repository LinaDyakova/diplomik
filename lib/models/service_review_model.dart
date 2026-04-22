class ServiceReviewModel {
  final int id;
  final int serviceId;
  final String userId;
  final int rating;
  final String comment;
  final DateTime createdAt;

  ServiceReviewModel({
    required this.id,
    required this.serviceId,
    required this.userId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory ServiceReviewModel.fromJson(Map<String, dynamic> json) {
    return ServiceReviewModel(
      id: json['id'],
      serviceId: json['service_id'],
      userId: json['user_id'],
      rating: json['rating'],
      comment: json['comment'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}