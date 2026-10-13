import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../state/invite_code_controller.dart';

/// Settings' Invite card: the code, copy, share (OS share sheet), a QR
/// code, Rotate (confirm), and optional expiry/max-uses — all backed by
/// migration 0111 (`invite_expires_at`/`invite_max_uses`/`invite_use_count`
/// + `fn_set_group_invite_limits`). The invite's deep link
/// (`https://myapp.example/join/<CODE>`) is only ever shown/encoded here;
/// nothing new reads it server-side yet, so joining still happens by
/// typing the code in-app — the QR/share just make handing out that code
/// easier.
class SettingsInviteCard extends StatefulWidget {
  const SettingsInviteCard({required this.controller, super.key});

  final InviteCodeController controller;

  @override
  State<SettingsInviteCard> createState() => _SettingsInviteCardState();
}

class _SettingsInviteCardState extends State<SettingsInviteCard> {
  InviteCodeController get _i => widget.controller;

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied.')),
    );
  }

  Future<void> _share(String code) async {
    await SharePlus.instance.share(
      ShareParams(text: 'Join my group on My Preparation — use code $code to join.'),
    );
  }

  void _showQr(String code) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan to join'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              key: const Key('invite_qr_code'),
              data: code,
              size: 220,
            ),
            const SizedBox(height: 12),
            Text(code, style: const TextStyle(fontFamily: 'monospace', letterSpacing: 2)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _rotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rotate invite code?'),
        content: const Text(
          'The current code will stop working immediately. Anyone who has not '
          'joined yet will need the new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_rotate'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Rotate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _i.rotate();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Invite code rotated.' : (_i.error ?? 'Could not rotate the code.')),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }

  Future<void> _editLimits() async {
    var expiresAt = _i.expiresAt;
    final maxUsesCtrl = TextEditingController(text: _i.maxUses?.toString() ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Invite limits'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      expiresAt == null
                          ? 'No expiry'
                          : 'Expires ${expiresAt!.toLocal()}'.split('.').first,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDate: expiresAt ?? DateTime.now().add(const Duration(days: 7)),
                      );
                      if (picked != null) setState(() => expiresAt = picked);
                    },
                    child: const Text('Set date'),
                  ),
                  if (expiresAt != null)
                    IconButton(
                      key: const Key('clear_invite_expiry'),
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => expiresAt = null),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('invite_max_uses_field'),
                controller: maxUsesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max uses (blank = unlimited)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_invite_limits'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final maxUsesText = maxUsesCtrl.text.trim();
    final maxUses = maxUsesText.isEmpty ? null : int.tryParse(maxUsesText);
    if (maxUsesText.isNotEmpty && (maxUses == null || maxUses <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Max uses must be a positive number, or left blank.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final ok = await _i.setLimits(expiresAt: expiresAt, maxUses: maxUses);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Invite limits updated.' : (_i.error ?? 'Could not update limits.')),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('invite_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Invite', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Share this code so people can join. Rotating it invalidates the old '
          'code immediately.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_i.isLoading && !_i.hasLoaded)
          const Padding(
            key: Key('invite_loading'),
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else if (_i.code == null)
          Row(
            children: [
              Expanded(
                child: Text(
                  _i.error ?? 'Invite code is not available.',
                  key: const Key('invite_error'),
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              TextButton(
                key: const Key('invite_retry'),
                onPressed: _i.isBusy ? null : _i.retry,
                child: const Text('Retry'),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _i.code!,
                  key: const Key('invite_code_value'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
              ),
              IconButton(
                key: const Key('invite_copy'),
                tooltip: 'Copy invite code',
                icon: const Icon(Icons.copy_outlined),
                onPressed: _i.isBusy ? null : () => _copy(_i.code!),
              ),
              IconButton(
                key: const Key('invite_share'),
                tooltip: 'Share invite',
                icon: const Icon(Icons.ios_share_outlined),
                onPressed: _i.isBusy ? null : () => _share(_i.code!),
              ),
              IconButton(
                key: const Key('invite_qr'),
                tooltip: 'Show QR code',
                icon: const Icon(Icons.qr_code_2_outlined),
                onPressed: () => _showQr(_i.code!),
              ),
            ],
          ),
          if (_i.error != null)
            Text(
              _i.error!,
              key: const Key('invite_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          if (_i.justRotated && _i.error == null)
            const Text(
              'New code generated.',
              key: Key('invite_rotated'),
              style: TextStyle(color: AppColors.success),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: AppRadius.mdBorder,
            ),
            child: Row(
              key: const Key('invite_limits_summary'),
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _limitsSummary(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  key: const Key('edit_invite_limits'),
                  onPressed: _i.isBusy ? null : _editLimits,
                  child: const Text('Edit'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('invite_rotate'),
            onPressed: _i.isBusy ? null : _rotate,
            icon: const Icon(Icons.refresh),
            label: Text(_i.isRotating ? 'Rotating…' : 'Rotate invite code'),
          ),
        ],
      ],
    );
  }

  String _limitsSummary() {
    final parts = <String>[];
    parts.add(
      _i.expiresAt == null
          ? 'No expiry'
          : 'Expires ${_i.expiresAt!.toLocal()}'.split('.').first,
    );
    parts.add(
      _i.maxUses == null
          ? '${_i.useCount} use${_i.useCount == 1 ? '' : 's'} so far, no limit'
          : '${_i.useCount}/${_i.maxUses} uses',
    );
    return parts.join(' · ');
  }
}
