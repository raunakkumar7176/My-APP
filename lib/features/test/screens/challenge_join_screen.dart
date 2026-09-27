import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../state/challenge_controller.dart';

/// `/tests/join` — a candidate enters the host's 6-digit examination PIN
/// (`rpc_join_challenge_session`) and is dropped into the real-time waiting
/// room to await the host's "Commence" action.
class ChallengeJoinScreen extends StatefulWidget {
  const ChallengeJoinScreen({this.controller, super.key});

  final ChallengeController? controller;

  @override
  State<ChallengeJoinScreen> createState() => _ChallengeJoinScreenState();
}

class _ChallengeJoinScreenState extends State<ChallengeJoinScreen> {
  late final ChallengeController _c;
  final _pinController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = widget.controller ?? ChallengeController();
  }

  @override
  void dispose() {
    _pinController.dispose();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6 || int.tryParse(pin) == null) {
      setState(() => _error = 'Enter the 6-digit examination PIN.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    await _c.joinByPin(pin);
    if (!mounted) return;
    if (_c.error != null) {
      setState(() {
        _submitting = false;
        _error = _c.error;
      });
      return;
    }
    context.pushReplacement(
      '/challenge/${_c.session!.id}/waiting-room',
      extra: _c,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a Peer Challenge')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pin_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Enter the 6-digit PIN your host shared with you.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('challenge_pin_field'),
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '000000',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('challenge_join_btn'),
                  onPressed: _submitting ? null : _join,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Join Examination'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
