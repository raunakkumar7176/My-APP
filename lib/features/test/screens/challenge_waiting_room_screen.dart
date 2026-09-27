import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/models/challenge_session.dart';
import '../state/attempt_launch_store.dart';
import '../state/challenge_controller.dart';
import '../state/test_detail_controller.dart';

/// Host creates a session (or a candidate joins by PIN) and lands here.
/// Shows the live roster (Realtime), lets the host commence, then shows the
/// synchronized "Examination begins in 5…4…3…2…1" countdown driven by the
/// server's `commence_at` timestamp before opening the real, existing live
/// attempt screen (`/attempts/:id/take`) — the actual exam is never
/// reimplemented here, only the pre-exam synchronization is.
class ChallengeWaitingRoomScreen extends StatefulWidget {
  const ChallengeWaitingRoomScreen({
    this.sessionId,
    this.controller,
    super.key,
  });

  /// Present when arriving via a route (e.g. after joining by PIN and
  /// navigating here with just the id).
  final String? sessionId;

  /// Injectable for tests / when the caller already created the session.
  final ChallengeController? controller;

  @override
  State<ChallengeWaitingRoomScreen> createState() =>
      _ChallengeWaitingRoomScreenState();
}

class _ChallengeWaitingRoomScreenState
    extends State<ChallengeWaitingRoomScreen> {
  late final ChallengeController _c;
  late final bool _owns;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? ChallengeController();
    _c.addListener(_onChanged);
    if (widget.controller == null && widget.sessionId != null) {
      _c.loadSession(widget.sessionId!);
    }
    _maybeStartCountdown();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeStartCountdown();
  }

  void _maybeStartCountdown() {
    final commenceAt = _c.session?.commenceAt;
    if (commenceAt == null || _c.session?.status != 'commenced') {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }
    _countdownTimer ??= Timer.periodic(const Duration(milliseconds: 200), (_) {
      final left = commenceAt.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _remaining = left.isNegative ? Duration.zero : left);
      if (left <= Duration.zero) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        _startAttempt();
      }
    });
  }

  Future<void> _startAttempt() async {
    if (_launching) return;
    final testId = _c.session?.testId;
    if (testId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This session has no linked test paper. Contact the host.',
            ),
          ),
        );
      }
      return;
    }
    setState(() => _launching = true);
    try {
      final detail = TestDetailController(testId: testId);
      await detail.load();
      final launched = await detail.start();
      if (!mounted) return;
      AttemptLaunchStore.putLaunch(
        started: launched.started,
        questions: launched.questions,
        test: launched.test,
      );
      await _c.bindAttempt(launched.started.attempt.id);
      if (!mounted) return;
      context.pushReplacement(
        '/attempts/${launched.started.attempt.id}/take?test=${launched.started.attempt.testId}&challenge=${_c.session!.id}',
      );
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _launching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _launching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the exam. Please try again.')),
      );
    }
  }

  Future<void> _onCommence() async {
    await _c.commence();
    if (!mounted) return;
    if (_c.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_c.error!)),
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _c.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Peer Challenge — Waiting Room')),
      body: _c.isLoading && session == null
          ? const Center(child: CircularProgressIndicator())
          : session == null
              ? Center(
                  child: Text(_c.error ?? 'Session not found.'),
                )
              : session.isCommenced
                  ? _buildCountdown(session)
                  : _buildWaitingRoom(session),
    );
  }

  Widget _buildWaitingRoom(ChallengeSession session) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(session.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(session.subject, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          Container(
            key: const Key('challenge_pin_display'),
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text('Examination PIN', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(
                  session.pinCode,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Candidates (${_c.roster.length})',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._c.roster.map(
            (p) => ListTile(
              key: Key('challenge_participant_${p.userId}'),
              leading: CircleAvatar(
                child: Text(
                  p.candidateName.isNotEmpty
                      ? p.candidateName[0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(p.candidateName),
              subtitle: Text(p.candidateCode ?? ''),
              trailing: p.isHost
                  ? const Chip(label: Text('Host'))
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          if (_c.isHost)
            FilledButton(
              key: const Key('commence_challenge_btn'),
              onPressed: _c.isLoading ? null : _onCommence,
              child: const Text('Commence Examination'),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: Text('Waiting for the host to commence…')),
            ),
        ],
      ),
    );
  }

  Widget _buildCountdown(ChallengeSession session) {
    final seconds = (_remaining.inMilliseconds / 1000).ceil().clamp(0, 999);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Examination begins in',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            '$seconds',
            key: const Key('challenge_countdown_seconds'),
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
