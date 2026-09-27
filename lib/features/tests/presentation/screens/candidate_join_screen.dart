import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_error.dart';
import '../../../../core/services/profile_service.dart';
import '../../services/peer_challenge_service.dart';

/// Screen: Candidate Join / Examination PIN Entry
/// High-contrast academic desk allowing examinees to input a 6-digit PIN
/// and enter the live Candidate Waiting Room.
class CandidateJoinScreen extends StatefulWidget {
  const CandidateJoinScreen({super.key});

  @override
  State<CandidateJoinScreen> createState() => _CandidateJoinScreenState();
}

class _CandidateJoinScreenState extends State<CandidateJoinScreen> {
  final TextEditingController _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isJoining = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _onJoinExamination() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _isJoining = true;
      _errorMessage = null;
    });

    try {
      final pin = _pinController.text.trim();
      final session = await PeerChallengeService.instance.joinSessionByPin(pin);
      if (!mounted) return;

      context.push(
        '/tests/challenge/$pin/waiting-room',
        extra: session,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is AppError ? e.message : 'Invalid Examination PIN. Please verify.';
      });
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final profile = ProfileService.currentProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Candidate Hall Entry',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Academic Insignia
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.pin_outlined,
                      size: 38,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'Enter Examination PIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Input the 6-digit synchronized test code provided by your invigilator or peer host.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // PIN Input Field
                  TextFormField(
                    key: const Key('challenge_pin_input'),
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                      color: Color(0xFF2563EB),
                    ),
                    decoration: InputDecoration(
                      hintText: '••••••',
                      counterText: '',
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF2563EB),
                          width: 2.2,
                        ),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().length != 6) {
                        return 'PIN must be exactly 6 digits';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Error notification if any
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFDC2626)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Candidate Verification Strip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.badge_outlined, size: 20, color: Color(0xFF64748B)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?.fullName.isNotEmpty == true
                                    ? profile!.fullName
                                    : 'Aspirant Candidate',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Roll No: ${profile?.studentCode ?? 'MP-ENROLLED'}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Button
                  FilledButton.icon(
                    key: const Key('enter_waiting_room_btn'),
                    onPressed: _isJoining ? null : _onJoinExamination,
                    icon: _isJoining
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded, size: 18),
                    label: Text(
                      _isJoining
                          ? 'Verifying Examination PIN...'
                          : 'Admit to Waiting Room ➔',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
