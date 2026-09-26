import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/profile_service.dart';
import '../widgets/unique_id_search_sheet.dart';
import '../widgets/user_promotion_modal.dart';

/// Community Hub Screen: Public guidelines, announcements, and support desk
/// for all students, plus a restricted Founder Command Desk for app owners.
class CommunityHubScreen extends StatefulWidget {
  const CommunityHubScreen({this.isOwnerOverride, super.key});

  /// Override flag for unit/widget testing of the owner command tab.
  final bool? isOwnerOverride;

  @override
  State<CommunityHubScreen> createState() => _CommunityHubScreenState();
}

class _CommunityHubScreenState extends State<CommunityHubScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool _isLoadingRequests = false;
  List<Map<String, dynamic>> _verificationRequests = [];
  String? _requestsError;

  bool get _isOwner {
    if (widget.isOwnerOverride != null) return widget.isOwnerOverride!;
    return ProfileService.currentProfile?.appRole == AppRole.owner;
  }

  @override
  void initState() {
    super.initState();
    _initTabs();
    if (_isOwner) {
      _loadVerificationRequests();
    }
  }

  void _initTabs() {
    if (_isOwner) {
      _tabController = TabController(length: 2, vsync: this);
    }
  }

  @override
  void didUpdateWidget(covariant CommunityHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isOwner && _tabController == null) {
      _initTabs();
      _loadVerificationRequests();
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadVerificationRequests() async {
    setState(() {
      _isLoadingRequests = true;
      _requestsError = null;
    });

    try {
      final requests = await ProfileService.fetchPendingVerificationRequests();
      if (!mounted) return;
      setState(() {
        _verificationRequests = requests;
        _isLoadingRequests = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _requestsError = 'Failed to load verification requests.';
        _isLoadingRequests = false;
      });
    }
  }

  Future<void> _approveRequest(String requestId, String studentName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Blue Tick?'),
        content: Text(
          'Grant Verified Scholar badge and VIP status to $studentName?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ProfileService.approveVerificationRequest(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verified badge granted to $studentName!'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadVerificationRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _rejectRequest(String requestId, String studentName) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Provide a brief reason for declining $studentName:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'e.g. Incomplete profile or suspicious activity',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final reason = reasonController.text.trim().isEmpty
          ? 'Application does not meet current verification standards.'
          : reasonController.text.trim();
      await ProfileService.rejectVerificationRequest(requestId, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Declined verification for $studentName.')),
      );
      _loadVerificationRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _sweepExpiredBadges() async {
    try {
      final count = await ProfileService.checkAndRevokeBadges();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Badge sweep completed. Expired badges revoked: $count',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to sweep badges: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showBroadcastDialog() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.campaign_rounded, color: Color(0xFF7C3AED)),
            SizedBox(width: 8),
            Text('Broadcast Announcement'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Announcement Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Announcement Body',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
            ),
            onPressed: () {
              if (titleController.text.trim().isEmpty) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Announcement broadcasted to Community!'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: const Text('Broadcast'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Hub'),
        actions: [
          IconButton(
            tooltip: 'Search Student by ID',
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => UniqueIdSearchSheet.show(context),
          ),
        ],
        bottom: _isOwner && _tabController != null
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.public), text: 'Community'),
                  Tab(
                    icon: Icon(Icons.admin_panel_settings),
                    text: 'Founder Desk',
                  ),
                ],
              )
            : null,
      ),
      body: _isOwner && _tabController != null
          ? TabBarView(
              controller: _tabController,
              children: [
                _buildPublicView(isDark, theme),
                _buildFounderDesk(isDark, theme),
              ],
            )
          : _buildPublicView(isDark, theme),
    );
  }

  Widget _buildPublicView(bool isDark, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () async {
        if (mounted) setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Welcome Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFBFDBFE),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Color(0xFF2563EB),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'My Preparation Cohort',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'A distraction-free academic sanctuary. Connect with verified scholars, compare study consistency, and prepare with focused peers.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => UniqueIdSearchSheet.show(context),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Find Classmate by Unique ID'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Community Announcements
          Text(
            'Announcements & Updates',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          _buildAnnouncementCard(
            title: 'Weekly All-India JEE & NEET Mock Series',
            date: 'Live Now',
            body: 'Cohort leaderboards update every Sunday midnight UTC. Top 5 scholars receive permanent badges.',
            isDark: isDark,
            isImportant: true,
          ),
          const SizedBox(height: 10),
          _buildAnnouncementCard(
            title: 'Verified Scholar Blue Tick Policy v1.0',
            date: 'System',
            body: 'Aspirants with 1000+ points can apply for Blue Tick from Profile screen. Requests are reviewed by Founder Desk.',
            isDark: isDark,
          ),

          const SizedBox(height: 24),

          // Academic Guidelines
          Text(
            'Code of Conduct & Guidelines',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          _buildGuidelineTile(
            icon: Icons.verified_user_outlined,
            title: 'Academic Integrity & Honesty',
            description: 'Never cheat or automate answers in tests and practice. Points earned deceptively result in permanent account suspension.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildGuidelineTile(
            icon: Icons.forum_outlined,
            title: 'Zero Spam & Promotion',
            description: 'Commercial links, coaching promotions, and inappropriate links are strictly barred. Group chats auto-purge every 7 days.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildGuidelineTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Student Identity Protection',
            description: 'Profiles are searchable only through exact Student ID codes (e.g. MP-xxxxx). Names cannot be scanned or harvested.',
            isDark: isDark,
          ),

          const SizedBox(height: 24),

          // Help & Support Desk
          Text(
            'Student Help & Support Desk',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE0E7FF),
                      child: Icon(Icons.help_outline, color: Color(0xFF4338CA)),
                    ),
                    title: const Text('Verification & Points FAQ'),
                    subtitle: const Text(
                      'Understand how study points and blue tick reviews work',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _showFaqDialog();
                    },
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFEF3C7),
                      child: Icon(Icons.mail_outline, color: Color(0xFFD97706)),
                    ),
                    title: const Text('Contact Support / Report Issue'),
                    subtitle: const Text('support@mypreparation.app'),
                    trailing: const Icon(Icons.copy, size: 18),
                    onTap: () {
                      Clipboard.setData(
                        const ClipboardData(text: 'support@mypreparation.app'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Support email copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFounderDesk(bool isDark, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadVerificationRequests,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Founder Header Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF581C87), Color(0xFF3B0764)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0xFFF3E8FF),
                  child: Icon(
                    Icons.shield_rounded,
                    color: Color(0xFF7C3AED),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Founder & Owner Command Desk',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Verification applications, badge revocations, & cohorts.',
                        style: TextStyle(
                          color: Colors.purple[100],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Actions Row
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => UserPromotionModal.show(
                    context,
                    onPromoted: _loadVerificationRequests,
                  ),
                  icon: const Icon(Icons.military_tech_rounded, size: 18),
                  label: const Text('Promote User'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showBroadcastDialog,
                  icon: const Icon(Icons.campaign, size: 18),
                  label: const Text('Broadcast'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sweepExpiredBadges,
                  icon: const Icon(Icons.timer_off_outlined, size: 18),
                  label: const Text('Sweep Badges'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Queue Section Header
          Row(
            children: [
              Text(
                'Verification Request Queue',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_verificationRequests.length}',
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Queue',
                onPressed: _loadVerificationRequests,
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_isLoadingRequests)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_requestsError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C1618)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(_requestsError!),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loadVerificationRequests,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (_verificationRequests.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 48,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'All caught up!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'There are no pending verification requests at this moment.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._verificationRequests.map((req) {
              final requestId = req['id'] as String;
              final profiles = req['profiles'] as Map<String, dynamic>?;
              final studentName =
                  profiles?['full_name'] as String? ?? 'Applicant';
              final studentCode =
                  profiles?['student_code'] as String? ?? 'MP-*****';
              final points =
                  req['current_points'] as int? ??
                  profiles?['total_points'] as int? ??
                  0;
              final avatarUrl = profiles?['avatar_url'] as String?;

              return Card(
                key: Key('verification_request_$requestId'),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundImage:
                                avatarUrl != null && avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? Text(
                                    studentName.isNotEmpty
                                        ? studentName[0]
                                        : '?',
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  studentName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      studentCode,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.stars_rounded,
                                      size: 14,
                                      color: Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '$points pts',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.military_tech_rounded,
                              size: 20,
                              color: Color(0xFF7C3AED),
                            ),
                            tooltip: 'Promote with Custom Role',
                            onPressed: () => UserPromotionModal.show(
                              context,
                              initialStudentCode: studentCode,
                              onPromoted: _loadVerificationRequests,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                            ),
                            onPressed: () =>
                                _rejectRequest(requestId, studentName),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Decline'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                            ),
                            onPressed: () =>
                                _approveRequest(requestId, studentName),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Approve & Grant Blue Tick'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard({
    required String title,
    required String date,
    required String body,
    required bool isDark,
    bool isImportant = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isImportant
              ? const Color(0xFF2563EB).withValues(alpha: 0.4)
              : isDark
              ? const Color(0xFF334155)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isImportant
                      ? const Color(0xFF2563EB).withValues(alpha: 0.1)
                      : isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  date,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isImportant
                        ? const Color(0xFF2563EB)
                        : isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidelineTile({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFaqDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verification & Points FAQ'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Q: How do I earn study points?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'A: Points are awarded automatically when completing practice sets, chapter assessments, and group tests.',
              ),
              SizedBox(height: 12),
              Text(
                'Q: Who is eligible for the Blue Tick badge?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'A: Any aspirant with 1000+ points and a complete profile can apply. Founder review takes 24-48 hours.',
              ),
              SizedBox(height: 12),
              Text(
                'Q: Does the verified badge expire?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'A: Scholar badges remain active for 90 days. Ongoing study consistency renews the badge automatically.',
              ),
            ],
          ),
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
}
