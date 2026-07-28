import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../models/paginated_response.dart';
import '../models/payment_models.dart';

class PaymentRepository {
  PaymentRepository(this._api);

  final ApiClient _api;

  Future<PaginatedResponse<Payment>> myPayments({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.payments,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, Payment.fromJson);
  }

  Future<Payment> createPayment({
    required String courseId,
    required double amount,
    required String paymentMethod,
    String? transactionId,
  }) async {
    final response = await _api.post(ApiConfig.paymentCreate, data: {
      'course': courseId,
      'amount': amount,
      'payment_method': paymentMethod,
      'status': 'pending',
      if (transactionId != null) 'transaction_id': transactionId,
    });
    return Payment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Wallet> getWallet() async {
    final response = await _api.get(ApiConfig.wallet);
    return Wallet.fromJson(response.data as Map<String, dynamic>);
  }
}
