/// Matches Django REST Framework's PageNumberPagination response shape:
/// { "count": 20, "next": "...", "previous": null, "results": [...] }
class PaginatedResponse<T> {
  PaginatedResponse({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  final int count;
  final String? next;
  final String? previous;
  final List<T> results;

  bool get hasNext => next != null;

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final rawResults = json['results'];
    final list = (rawResults is List) ? rawResults : <dynamic>[];
    return PaginatedResponse(
      count: json['count'] is int ? json['count'] as int : 0,
      next: json['next'] as String?,
      previous: json['previous'] as String?,
      results: list
          .whereType<Map<String, dynamic>>()
          .map(fromJsonT)
          .toList(growable: false),
    );
  }

  /// Some endpoints might respond with a plain list (no pagination
  /// wrapper) — this helper handles both cases defensively.
  static PaginatedResponse<T> fromDynamic<T>(
    dynamic json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    if (json is List) {
      return PaginatedResponse(
        count: json.length,
        next: null,
        previous: null,
        results: json
            .whereType<Map<String, dynamic>>()
            .map(fromJsonT)
            .toList(growable: false),
      );
    }
    return PaginatedResponse.fromJson(json as Map<String, dynamic>, fromJsonT);
  }
}
