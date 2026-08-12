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
  Wallet({
    required this.id,
    required this.userId,
    this.balance = 0,
    this.momoWalletNumber,
    this.airtelMerchantNumber,
  });
  
  final String id;
  final String userId;
  final double balance;
  final String? momoWalletNumber;
  final String? airtelMerchantNumber;
  
  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: parseString(json['id']),
      userId: parseString(json['user']),
      balance: parseDouble(json['balance']),
      momoWalletNumber: json['momo_wallet_number'] as String?,
      airtelMerchantNumber: json['airtel_merchant_number'] as String?,
    );
  }
}

class WalletTopUpRequest {
  WalletTopUpRequest({
    required this.id,
    required this.userId,
    required this.amount,
    this.paymentMethod = 'mtn',
    required this.momoReference,
    this.status = 'pending',
    this.createdAt,
  });
  
  final String id;
  final String userId;
  final double amount;
  final String paymentMethod; // mtn | airtel
  final String momoReference;
  final String status; // pending | approved | rejected
  final DateTime? createdAt;
  
  factory WalletTopUpRequest.fromJson(Map<String, dynamic> json) {
    return WalletTopUpRequest(
      id: parseString(json['id']),
      userId: parseString(json['user']),
      amount: parseDouble(json['amount']),
      paymentMethod: parseString(json['payment_method'], fallback: 'mtn'),
      momoReference: parseString(json['momo_reference']),
      status: parseString(json['status'], fallback: 'pending'),
      createdAt: parseDate(json['created_at']),
    );
  }
}

class WithdrawalRequest {
  WithdrawalRequest({
    required this.id,
    required this.teacherId,
    required this.amount,
    required this.momoNumber,
    this.status = 'pending',
    this.createdAt,
  });
  
  final String id;
  final String teacherId;
  final double amount;
  final String momoNumber;
  final String status; // pending | approved | rejected
  final DateTime? createdAt;
  
  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) {
    return WithdrawalRequest(
      id: parseString(json['id']),
      teacherId: parseString(json['teacher']),
      amount: parseDouble(json['amount']),
      momoNumber: parseString(json['momo_number']),
      status: parseString(json['status'], fallback: 'pending'),
      createdAt: parseDate(json['created_at']),
    );
  }
