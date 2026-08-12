class _TopUpDialog extends ConsumerStatefulWidget {
  const _TopUpDialog();

  @override
  ConsumerState<_TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends ConsumerState<_TopUpDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _refController = TextEditingController();

  bool _submitting = false;
  String _paymentMethod = 'mtn';

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
    });

    try {
      await ref.read(paymentRepositoryProvider).submitTopUpRequest(
            amount: double.parse(
              _amountController.text.trim(),
            ),
            paymentMethod: _paymentMethod,
            momoReference: _refController.text.trim(),
          );

      ref.invalidate(myTopUpsProvider);
      ref.invalidate(walletProvider);

      if (mounted) {
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Top-up request submitted — an admin will review it shortly.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.message
            : 'Could not submit the request.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);

    final mtnNumber =
        walletAsync.asData?.value.momoWalletNumber ?? '';

    final airtelNumber =
        walletAsync.asData?.value.airtelMerchantNumber ?? '';

    final activeNumber =
        _paymentMethod == 'mtn'
            ? mtnNumber
            : airtelNumber;

    final activeLabel =
        _paymentMethod == 'mtn'
            ? 'MTN Mobile Money'
            : 'Airtel Merchant';

    return AlertDialog(
      title: const Text(
        'Top up your wallet',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose the network you sent from',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              // ---------------------------------------------------------
              // MTN / AIRTEL TOGGLE
              // ---------------------------------------------------------

              Container(
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(12),
                  border: Border.all(
                    color: _paymentMethod == 'mtn'
                        ? Colors.yellow.shade700
                        : Colors.red.shade700,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    // ---------------------------------------------------
                    // MTN
                    // ---------------------------------------------------

                    Expanded(
                      child: GestureDetector(
                        onTap: _submitting
                            ? null
                            : () {
                                setState(() {
                                  _paymentMethod =
                                      'mtn';
                                });
                              },
                        child: AnimatedContainer(
                          duration:
                              const Duration(
                            milliseconds: 200,
                          ),
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 12,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                _paymentMethod ==
                                        'mtn'
                                    ? Colors.yellow
                                        .shade700
                                    : Colors
                                        .transparent,
                            borderRadius:
                                const BorderRadius
                                    .horizontal(
                              left: Radius
                                  .circular(11),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .center,
                            children: [
                              Icon(
                                Icons
                                    .phone_android_rounded,
                                color:
                                    _paymentMethod ==
                                            'mtn'
                                        ? Colors
                                            .black
                                        : Colors
                                            .grey
                                            .shade700,
                              ),
                              const SizedBox(
                                width: 6,
                              ),
                              Text(
                                'MTN',
                                style:
                                    TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .w800,
                                  color:
                                      _paymentMethod ==
                                              'mtn'
                                          ? Colors
                                              .black
                                          : Colors
                                              .grey
                                              .shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ---------------------------------------------------
                    // AIRTEL
                    // ---------------------------------------------------

                    Expanded(
                      child: GestureDetector(
                        onTap: _submitting
                            ? null
                            : () {
                                setState(() {
                                  _paymentMethod =
                                      'airtel';
                                });
                              },
                        child: AnimatedContainer(
                          duration:
                              const Duration(
                            milliseconds: 200,
                          ),
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 12,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                _paymentMethod ==
                                        'airtel'
                                    ? Colors.red
                                        .shade700
                                    : Colors
                                        .transparent,
                            borderRadius:
                                const BorderRadius
                                    .horizontal(
                              right: Radius
                                  .circular(11),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .center,
                            children: [
                              Icon(
                                Icons
                                    .phone_android_rounded,
                                color:
                                    _paymentMethod ==
                                            'airtel'
                                        ? Colors
                                            .white
                                        : Colors
                                            .grey
                                            .shade700,
                              ),
                              const SizedBox(
                                width: 6,
                              ),
                              Text(
                                'Airtel',
                                style:
                                    TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .w800,
                                  color:
                                      _paymentMethod ==
                                              'airtel'
                                          ? Colors
                                              .white
                                          : Colors
                                              .grey
                                              .shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------
              // PAYMENT INSTRUCTIONS
              // ---------------------------------------------------------

              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _paymentMethod == 'mtn'
                      ? Colors.yellow
                          .shade50
                      : Colors.red.shade50,
                  borderRadius:
                      BorderRadius.circular(10),
                  border: Border.all(
                    color: _paymentMethod == 'mtn'
                        ? Colors.yellow
                            .shade700
                        : Colors.red
                            .shade700,
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeLabel,
                      style: TextStyle(
                        fontWeight:
                            FontWeight.w800,
                        color:
                            _paymentMethod ==
                                    'mtn'
                                ? Colors
                                    .yellow
                                    .shade900
                                : Colors
                                    .red
                                    .shade900,
                      ),
                    ),

                    const SizedBox(height: 6),

                    if (activeNumber
                        .isNotEmpty)
                      Text(
                        activeNumber,
                        style:
                            const TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.w800,
                        ),
                      ),

                    const SizedBox(height: 6),

                    Text(
                      activeNumber.isEmpty
                          ? 'Send money using $activeLabel, then enter the payment reference below.'
                          : 'Send money to $activeNumber using $activeLabel, then enter the payment reference below.',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------
              // AMOUNT
              // ---------------------------------------------------------

              AppTextField(
                controller:
                    _amountController,
                label: 'Amount (USD)',
                keyboardType:
                    const TextInputType
                        .numberWithOptions(
                  decimal: true,
                ),
                prefixIcon:
                    Icons.attach_money_rounded,
                validator: (v) {
                  final value =
                      double.tryParse(
                    (v ?? '').trim(),
                  );

                  if (value == null ||
                      value <= 0) {
                    return 'Enter a valid amount';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------
              // TRANSACTION REFERENCE
              // ---------------------------------------------------------

              AppTextField(
                controller:
                    _refController,
                label:
                    'Mobile payment reference ID',
                prefixIcon:
                    Icons.receipt_long_outlined,
                validator: (v) {
                  if (v == null ||
                      v.trim().isEmpty) {
                    return 'Enter the payment reference';
                  }

                  return null;
                },
              ),
            ],
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () =>
                  Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),

        FilledButton(
          onPressed:
              _submitting ? null : _submit,
          child: Text(
            _submitting
                ? 'Submitting…'
                : 'Submit',
          ),
        ),
      ],
    );
  }
}
