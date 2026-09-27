import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/referral_status.dart';
import '../../core/services/app_share_service.dart';
import '../../core/services/profile_service.dart';

/// Refer & Earn: share the caller's own `student_code` as a referral code.
/// +50 points to the referrer, +100 to the referee — both server-awarded by
/// `rpc_apply_referral` (migration 0066) once the referee enters this code.
/// This screen never awards or displays a point total it invented; the
/// summary shown comes from `rpc_get_my_referral_status`.
class ReferAndEarnScreen extends StatefulWidget {
  const ReferAndEarnScreen({super.key});

  @override
  State<ReferAndEarnScreen> createState() => _ReferAndEarnScreenState();
}

class _ReferAndEarnScreenState extends State<ReferAndEarnScreen> {
  ReferralStatus? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await ProfileService.getMyReferralStatus();
    if (mounted) setState(() => _status = status);
  }

  String get _code => ProfileService.currentProfile?.studentCode ?? '';

  Future<void> _share() async {
    final shared = await AppShareService.shareApp();
    if (!shared && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your profile is still loading. Try again in a moment.')),
      );
    }
  }

  Future<void> _copy() async {
    if (_code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referral code copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Refer & Earn')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.card_giftcard_outlined, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'Give 100, Get 50',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your friend gets +100 study points when they sign up with '
                    'your code, and you get +50.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Your referral code', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _code.isEmpty ? '—' : _code,
                    key: const Key('referral_code_text'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  IconButton(
                    key: const Key('referral_copy_btn'),
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: 'Copy',
                    onPressed: _copy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('referral_share_btn'),
              onPressed: _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share with Friends'),
            ),
            const SizedBox(height: 24),
            if (_status != null) ...[
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statColumn('${_status!.referralCount}', 'Friends Referred'),
                  _statColumn('${_status!.pointsEarned}', 'Points Earned'),
                ],
              ),
              if (_status!.hasBeenReferred) ...[
                const SizedBox(height: 12),
                Text(
                  'You joined using someone else\'s referral code.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _statColumn(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label),
      ],
    );
  }
}
