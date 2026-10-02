import 'package:flutter/material.dart';
import '../../../core/constants/theme/app_colors.dart';
import '../../../core/services/settings/library_mode_controller.dart';

/// Unobtrusive top banner shown on the Dashboard when Library Mode is active.
/// Provides instant visual confirmation and tap-to-configure options for focus sessions.
class LibraryModeBanner extends StatelessWidget {
  const LibraryModeBanner({super.key});

  static void showFocusSessionSheet(BuildContext context) {
    final controller = LibraryModeController.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final isLibrary = controller.isLibraryMode;
          final remaining = controller.formattedRemainingTime;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('🤫', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Library Mode (Silent Shield)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isLibrary
                                  ? (remaining != null
                                      ? 'Session active • $remaining left'
                                      : 'All loud notification chimes muted')
                                  : 'Distraction-free silent study environment',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isLibrary,
                        activeThumbColor: const Color(0xFF2E7D32),
                        onChanged: (val) {
                          controller.setLibraryMode(val);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'START A TIMED FOCUS SESSION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SessionChip(
                        label: '30 Mins',
                        duration: const Duration(minutes: 30),
                        onSelected: () {
                          controller.startFocusSession(const Duration(minutes: 30));
                          Navigator.pop(ctx);
                        },
                      ),
                      _SessionChip(
                        label: '1 Hour',
                        duration: const Duration(hours: 1),
                        onSelected: () {
                          controller.startFocusSession(const Duration(hours: 1));
                          Navigator.pop(ctx);
                        },
                      ),
                      _SessionChip(
                        label: '2 Hours',
                        duration: const Duration(hours: 2),
                        onSelected: () {
                          controller.startFocusSession(const Duration(hours: 2));
                          Navigator.pop(ctx);
                        },
                      ),
                      _SessionChip(
                        label: '3 Hours',
                        duration: const Duration(hours: 3),
                        onSelected: () {
                          controller.startFocusSession(const Duration(hours: 3));
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Auto-activate during routine slots'),
                    subtitle: const Text('Silences app automatically when a study slot begins'),
                    value: controller.autoRoutineEnabled,
                    activeColor: const Color(0xFF2E7D32),
                    onChanged: (val) {
                      if (val != null) {
                        controller.setAutoRoutineEnabled(val);
                        setState(() {});
                      }
                    },
                  ),
                  if (isLibrary) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                        onPressed: () {
                          controller.setLibraryMode(false);
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.volume_up_outlined, size: 18),
                        label: const Text('Turn Off Library Mode'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LibraryModeController.instance,
      builder: (context, _) {
        final controller = LibraryModeController.instance;
        if (!controller.isLibraryMode) return const SizedBox.shrink();

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final remaining = controller.formattedRemainingTime;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF142B20) : const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF2E7D32) : const Color(0xFF86EFAC),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showFocusSessionSheet(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    const Text('🤫', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Library Mode Active • Distraction Free',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF81C784) : const Color(0xFF15803D),
                            ),
                          ),
                          Text(
                            remaining != null
                                ? 'Focus Session: $remaining remaining'
                                : 'Aawazein band hain, padhai par dhyan dein.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFFA5D6A7) : const Color(0xFF166534),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: isDark ? const Color(0xFF81C784) : const Color(0xFF15803D),
                      ),
                      onPressed: () => controller.setLibraryMode(false),
                      child: const Text(
                        'Disable',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SessionChip extends StatelessWidget {
  const _SessionChip({
    required this.label,
    required this.duration,
    required this.onSelected,
  });

  final String label;
  final Duration duration;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.timer_outlined, size: 16),
      label: Text(label),
      onPressed: onSelected,
    );
  }
}
