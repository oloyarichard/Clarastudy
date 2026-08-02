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

  /// Submits a mobile-money top-up request for an admin to manually review
  /// and approve, after the student has sent money to the platform's
  /// mobile money wallet outside the app.
  Future<void> submitTopUpRequest({
    required double amount,
    required String momoReference,
  }) async {
    await _api.post(ApiConfig.walletTopUp, data: {
      'amount': amount,
      'momo_reference': momoReference,
    });
  }

  /// The requesting student's own top-up requests, any status. The
  /// backend's TopUpRequestCreateView scopes GET to request.user already.
  Future<List<WalletTopUpRequest>> myTopUps() async {
    final response = await _api.get(ApiConfig.walletTopUp);
    final data = response.data;
    final results = data is Map<String, dynamic> ? (data['results'] ?? data) : data;
    return (results as List)
        .map((e) => WalletTopUpRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin-only: top-up requests still awaiting review.
  Future<List<WalletTopUpRequest>> listPendingTopUps() async {
    final response = await _api.get(ApiConfig.pendingTopUps);
    final data = response.data;
    final results = data is Map<String, dynamic> ? (data['results'] ?? data) : data;
    return (results as List)
        .map((e) => WalletTopUpRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin-only: approve credits the student's wallet; reject just closes it.
  Future<void> reviewTopUp(String topUpId, {required bool approve}) async {
    await _api.post(ApiConfig.reviewTopUp(topUpId), data: {'approve': approve});
  }

  /// Teacher-only: requests a payout to a mobile money number. The
  /// amount is held (deducted from the wallet) immediately by the
  /// backend, before an admin ever reviews it.
  Future<WithdrawalRequest> requestWithdrawal({
    required double amount,
    required String momoNumber,
  }) async {
    final response = await _api.post(ApiConfig.withdrawalRequest, data: {
      'amount': amount,
      'momo_number': momoNumber,
    });
    return WithdrawalRequest.fromJson(response.data as Map<String, dynamic>);
  }

  /// The requesting teacher's own withdrawal requests, any status.
  Future<List<WithdrawalRequest>> myWithdrawals() async {
    final response = await _api.get(ApiConfig.withdrawalRequest);
    final data = response.data;
    final results = data is Map<String, dynamic> ? (data['results'] ?? data) : data;
    return (results as List)
        .map((e) => WithdrawalRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin-only: withdrawal requests still awaiting review.
  Future<List<WithdrawalRequest>> listPendingWithdrawals() async {
    final response = await _api.get(ApiConfig.pendingWithdrawals);
    final data = response.data;
    final results = data is Map<String, dynamic> ? (data['results'] ?? data) : data;
    return (results as List)
        .map((e) => WithdrawalRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin-only: approve marks the payout as sent (money is sent
  /// off-platform to the teacher's mobile money number); reject refunds
  /// the held amount back to the teacher's wallet. Either way the
  /// teacher gets a notification (handled server-side).
  Future<void> reviewWithdrawal(String withdrawalId, {required bool approve}) async {
    await _api.post(ApiConfig.reviewWithdrawal(withdrawalId), data: {'approve': approve});
  }
}
