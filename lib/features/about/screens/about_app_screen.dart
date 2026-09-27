import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/widgets/app_logo.dart';

/// Dedicated "About App & Founder Desk" screen.
/// Route: `/about`
class AboutAppScreen extends StatefulWidget {
  const AboutAppScreen({super.key});

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  String? _founderUserId;

  @override
  void initState() {
    super.initState();
    _fetchFounderUserId();
  }

  Future<void> _fetchFounderUserId() async {
    if (!SupabaseService.isInitialized) {
      if (mounted) setState(() => _founderUserId = 'founder_official_uid');
      return;
    }
    try {
      final row = await SupabaseService.client
          .from('profiles')
          .select('id')
          .eq('app_role', 'owner')
          .limit(1)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _founderUserId = row?['id'] as String? ?? 'founder_official_uid';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _founderUserId = 'founder_official_uid';
        });
      }
    }
  }

  Future<void> _launchUrlStr(String urlStr) async {
    final uri = Uri.tryParse(urlStr);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showHelpDeskModal() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final viewInsets = MediaQuery.of(ctx).viewInsets;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF475569)
                          : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.support_agent_rounded,
                      color: Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Contact Support / Report Issue',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Have an issue with test sync, points, or content? Reach out directly.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Issue Subject',
                    hintText: 'e.g. Test submission sync problem',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Provide details on what occurred...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            const ClipboardData(
                              text: 'support@mypreparation.app',
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Support email copied to clipboard!',
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          Navigator.of(ctx).pop();
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy Email'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Support ticket logged. Our team will review within 24 hours.',
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        },
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Send Ticket'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About & Founder Desk'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Top Header & Vision
                _buildTopHeader(isDark, theme),

                const SizedBox(height: 24),

                // 2. The Founder Desk Card (VIP Card)
                _buildFounderDeskCard(isDark, theme),

                const SizedBox(height: 28),

                // 3. Core Team & Contributors
                _buildCoreTeamSection(isDark, theme),

                const SizedBox(height: 28),

                // 4. App Philosophy & How It Works
                _buildPhilosophySection(isDark, theme),

                const SizedBox(height: 28),

                // 5. Help Desk & Problem Solutions (FAQ)
                _buildFaqSection(isDark, theme),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(bool isDark, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // App Logo — the real My Preparation mark, not a placeholder icon.
          const AppLogo(size: 72),
          const SizedBox(height: 16),

          // App Name
          const Text(
            'My Preparation',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),

          // Mission Statement
          Text(
            'Built for serious competitive exam preparation.\nZero distraction, 100% student-focused.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),

          // Version badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'v1.0.0 • Production Build',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFounderDeskCard(bool isDark, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Founder Card Header Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'The Founder Desk',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD97706),
                    fontSize: 13.5,
                    letterSpacing: 0.5,
                  ),
                ),
                Spacer(),
                Text(
                  'VIP ARCHITECT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: Color(0xFFD97706),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar, Name & Title
                Row(
                  children: [
                    // Avatar with Golden Ring
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF59E0B),
                      ),
                      child: const CircleAvatar(
                        radius: 30,
                        backgroundColor: Color(0xFF1E293B),
                        child: Text(
                          'R',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Text(
                                'Raunak',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(width: 6),
                              Tooltip(
                                message: '👑 Official Founder',
                                child: Icon(
                                  Icons.verified_rounded,
                                  color: Color(0xFFF59E0B),
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Founder & Lead Architect',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Personal Message from Founder
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.format_quote_rounded,
                            size: 18,
                            color: Color(0xFFF59E0B),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'A Message to Every Aspirant',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '"I built My Preparation because serious students deserve an authentic, distraction-free environment. No gamified fluff, no hidden paywalls on core knowledge, and no data misuse.\n\nEvery feature — from strict Unique ID search to Chapter Assessment Hubs — is crafted to respect your focus, discipline, and hard work. Prepare fearlessly."',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Verified Social Links Strip
                Row(
                  children: [
                    Text(
                      'Connect with Founder:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const Spacer(),
                    _socialBtn(
                      icon: Icons.link,
                      color: const Color(0xFF0A66C2),
                      tooltip: 'LinkedIn',
                      url: 'https://linkedin.com',
                    ),
                    _socialBtn(
                      icon: Icons.alternate_email,
                      color: isDark ? Colors.white : Colors.black87,
                      tooltip: 'X / Twitter',
                      url: 'https://x.com',
                    ),
                    _socialBtn(
                      icon: Icons.code,
                      color: isDark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF181717),
                      tooltip: 'GitHub',
                      url: 'https://github.com/raunakkumar7176',
                    ),
                    _socialBtn(
                      icon: Icons.camera_alt_outlined,
                      color: const Color(0xFFE4405F),
                      tooltip: 'Instagram',
                      url: 'https://instagram.com',
                    ),
                    _socialBtn(
                      icon: Icons.play_arrow_outlined,
                      color: const Color(0xFFFF0000),
                      tooltip: 'YouTube',
                      url: 'https://youtube.com',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // View Founder Profile CTA Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final targetId = _founderUserId ?? 'founder_official_uid';
                      context.push(
                        '/profile/$targetId',
                        extra: ProfileService.fallbackFounderProfile,
                      );
                    },
                    icon: const Icon(
                      Icons.person_pin_circle_outlined,
                      size: 18,
                    ),
                    label: const Text('View Founder Profile'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD97706),
                      side: const BorderSide(color: Color(0xFFF59E0B)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required String url,
  }) {
    return IconButton(
      icon: Icon(icon, color: color, size: 20),
      tooltip: tooltip,
      onPressed: () => _launchUrlStr(url),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildCoreTeamSection(bool isDark, ThemeData theme) {
    final contributors = [
      (
        role: 'Lead Developer',
        subtitle: 'Platform Architecture & Real-Time Sync',
        badge: '⭐ Verified Core',
        icon: Icons.code_rounded,
        color: const Color(0xFF2563EB),
      ),
      (
        role: 'Academic Mentor',
        subtitle: 'Pedagogy, Syllabus & Question Bank',
        badge: '⭐ Verified Core',
        icon: Icons.auto_stories_rounded,
        color: const Color(0xFF7C3AED),
      ),
      (
        role: 'Content Advisor',
        subtitle: 'Competitive Exam Pattern Specialist',
        badge: '⭐ Verified Core',
        icon: Icons.psychology_rounded,
        color: const Color(0xFF10B981),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Core Team & Contributors',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...contributors.map((c) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: c.color.withValues(alpha: 0.12),
                  child: Icon(c.icon, color: c.color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.role,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    c.badge,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: c.color,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPhilosophySection(bool isDark, ThemeData theme) {
    final items = [
      (
        title: 'How Chapters (Learn + Assessment Hub) Work',
        icon: Icons.menu_book_rounded,
        color: const Color(0xFF2563EB),
        content: 'Each subject is structured into structured Chapter Outlines. First, master theory topics step-by-step. Then, transition to the unified Chapter Assessment Hub: practice with immediate feedback and no negative marking, or attempt formal locked chapter exams under real testing constraints.',
      ),
      (
        title: 'How 1,000 Points & 90-Day Blue Tick Work',
        icon: Icons.stars_rounded,
        color: const Color(0xFFD97706),
        content: 'Every test solved and practice goal achieved credits study points to your student ledger. Once you cross 1,000 study points, you unlock eligibility to apply for the Verified Scholar Blue Tick, reviewed and issued for 90 days of verified academic distinction.',
      ),
      (
        title: 'Strict Unique Student ID Policy (Anti-Spam)',
        icon: Icons.badge_rounded,
        color: const Color(0xFF10B981),
        content: 'To protect student privacy and eradicate spam, loose name searching is disabled across My Preparation. Students discover and follow peers exclusively using exact Unique Student Codes (e.g. MP-84920).',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'App Philosophy & How It Works',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Icon(item.icon, color: item.color, size: 22),
                  title: Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        item.content,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFaqSection(bool isDark, ThemeData theme) {
    final faqs = [
      (
        q: 'What happens if my network drops during a test?',
        a: 'All responses are cached locally on your device in real time. As soon as connectivity returns, your answers and completion timestamps automatically synchronize.',
      ),
      (
        q: 'Can I study chapter theory in offline mode?',
        a: 'Yes. Previously loaded chapter notes, formulas, and diagrams are saved in offline storage for distraction-free reading anywhere.',
      ),
      (
        q: 'How are weekly cohort points calculated?',
        a: 'Points accumulate from chapter assessments, mock tests, and practice accuracy. The cohort leaderboard resets every Sunday midnight UTC to keep competitions fresh and active.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Help Desk & Problem Solutions (FAQ)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...faqs.map((faq) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.help_outline_rounded,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                  title: Text(
                    faq.q,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        faq.a,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _showHelpDeskModal,
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text(
              '💬 Contact Support / Report Issue',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
