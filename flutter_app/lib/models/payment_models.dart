import 'parsing_utils.dart';

class Payment {
  Payment({
    required this.id,
    required this.userId,
    required this.courseId,
    required this.amount,
    required this.paymentMethod,
    this.status = 'pending',
    this.transactionId,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String courseId;
  final double amount;
  final String paymentMethod; // mtn_momo | card
  final String status; // pending | completed | failed
  final String? transactionId;
  final DateTime? createdAt;

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: parseString(json['id']),
      userId: parseString(json['user']),
      courseId: parseString(json['course']),
      amount: parseDouble(json['amount']),
      paymentMethod: parseString(json['payment_method'], fallback: 'card'),
      status: parseString(json['status'], fallback: 'pending'),
      transactionId: json['transaction_id'] as String?,
      createdAt: parseDate(json['created_at']),
    );
  }
}

class Wallet {
  Wallet({required this.id, required this.userId, this.balance = 0});

  final String id;
  final String userId;
  final double balance;

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: parseString(json['id']),
      userId: parseString(json['user']),
      balance: parseDouble(json['balance']),
    );
  }
}

class WalletTopUpRequest {
  WalletTopUpRequest({
    required this.id,
    required this.userId,
    required this.amount,
    required this.momoReference,
    this.status = 'pending',
    this.createdAt,
  });

  final String id;
  final String userId;
  final double amount;
  final String momoReference;
  final String status; // pending | approved | rejected
  final DateTime? createdAt;

  factory WalletTopUpRequest.fromJson(Map<String, dynamic> json) {
    return WalletTopUpRequest(
      id: parseString(json['id']),
      userId: parseString(json['user']),
      amount: parseDouble(json['amount']),
      momoReference: parseString(json['momo_reference']),
      status: parseString(json['status'], fallback: 'pending'),
      createdAt: parseDate(json['created_at']),
    );
  }
}
