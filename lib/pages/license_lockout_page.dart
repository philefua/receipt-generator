import 'package:flutter/material.dart';

import '../services/device_id_service.dart';
import '../services/license_service.dart';
import '../services/whatsapp_share_service.dart';

/// Full-screen lockout shown when the trial has expired and no active
/// subscription or Lifetime license exists. Lets the manager request a
/// plan via WhatsApp (device ID + chosen plan pre-filled) and enter an
/// activation code received in return.
class LicenseLockoutPage extends StatefulWidget {
  /// Called after a code is successfully redeemed, so the caller (Step 6's
  /// RootShell wiring) can re-check license status and dismiss this page.
  final VoidCallback? onLicenseActivated;

  const LicenseLockoutPage({super.key, this.onLicenseActivated});

  @override
  State<LicenseLockoutPage> createState() => _LicenseLockoutPageState();
}

class _LicenseLockoutPageState extends State<LicenseLockoutPage> {
  static const _licensingWhatsAppNumber = '+2348023920619';

  static const Map<PlanTier, String> _planDisplayNames = {
    PlanTier.oneMonth: '1 Month',
    PlanTier.threeMonths: '3 Months',
    PlanTier.sixMonths: '6 Months',
    PlanTier.oneYear: '1 Year',
    PlanTier.lifetime: 'Lifetime',
  };

  String? _deviceId;
  PlanTier? _selectedPlan;
  final _codeController = TextEditingController();

  bool _isRedeeming = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    final id = await DeviceIdService.instance.getDeviceId();
    if (mounted) setState(() => _deviceId = id);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendWhatsAppRequest() async {
    if (_selectedPlan == null || _deviceId == null) return;

    final planName = _planDisplayNames[_selectedPlan]!;
    final message =
        'Hi, I need a license activation code for Receipt Generator.\n\n'
        'Device ID: $_deviceId\n'
        'Requested plan: $planName';

    final result = await WhatsappShareService.instance.openWhatsAppChat(
      phoneNumber: _licensingWhatsAppNumber,
      message: message,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() => _errorMessage = result.message);
    }
  }

  String _errorText(ActivationCodeError error) {
    switch (error) {
      case ActivationCodeError.badFormat:
        return 'That code doesn\'t look right. Please check it and try again.';
      case ActivationCodeError.badSignature:
        return 'This code isn\'t valid. Please contact support.';
      case ActivationCodeError.deviceMismatch:
        return 'This code was issued for a different device.';
      case ActivationCodeError.alreadyRedeemed:
        return 'This code has already been used on this device.';
    }
  }

  Future<void> _redeemCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isRedeeming = true;
      _errorMessage = null;
    });

    final result = await LicenseService.instance.redeemActivationCode(code);

    if (!mounted) return;

    setState(() => _isRedeeming = false);

    if (result.isValid) {
      widget.onLicenseActivated?.call();
    } else {
      setState(() => _errorMessage = _errorText(result.error!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_clock_outlined, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Your trial or license has expired',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a plan and request an activation code, or enter '
                    'a code you already have.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  DropdownButtonFormField<PlanTier>(
                    initialValue: _selectedPlan,
                    decoration: const InputDecoration(
                      labelText: 'Select a plan',
                      border: OutlineInputBorder(),
                    ),
                    items: _planDisplayNames.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedPlan = value),
                  ),
                  const SizedBox(height: 12),

                  FilledButton.icon(
                    onPressed: _selectedPlan == null || _deviceId == null
                        ? null
                        : _sendWhatsAppRequest,
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Request via WhatsApp'),
                  ),

                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'Activation code',
                      border: OutlineInputBorder(),
                      hintText: 'XXXXX-XXXXX-XXXXX-...',
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 12),

                  FilledButton(
                    onPressed: _isRedeeming ? null : _redeemCode,
                    child: _isRedeeming
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Activate'),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],

                  if (_deviceId != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Device ID: $_deviceId',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}