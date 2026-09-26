import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/gamification_service.dart';
import '../../../core/services/profile_service.dart';

/// Modal bottom sheet that enables strict searching for any student by their
/// exact Unique Student ID (e.g. MP-84920).
///
/// Disallows loose name queries to preserve privacy and academic integrity.
class UniqueIdSearchSheet extends StatefulWidget {
  const UniqueIdSearchSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const UniqueIdSearchSheet(),
    );
  }

  @override
  State<UniqueIdSearchSheet> createState() => _UniqueIdSearchSheetState();
}

class _UniqueIdSearchSheetState extends State<UniqueIdSearchSheet> {
  final _searchController = TextEditingController();
  bool _isLoading = false;
  StudentSearchResult? _result;
  String? _errorMessage;
  bool _hasSearched = false;
  bool _isFollowing = false;
  bool _isFollowLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim().toUpperCase();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasSearched = true;
      _isFollowing = false;
    });

    try {
      final res = await GamificationService.searchStudentByCode(query);
      if (!mounted) return;
      setState(() {
        _result = res;
        _isLoading = false;
        if (res == null) {
          _errorMessage = 'No student found with this Unique ID.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Search failed. Please verify your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow(StudentSearchResult student) async {
    setState(() => _isFollowLoading = true);
    try {
      if (_isFollowing) {
        await ProfileService.unfollowUser(student.id);
        if (mounted) setState(() => _isFollowing = false);
      } else {
        await ProfileService.followUser(student.id);
        if (mounted) setState(() => _isFollowing = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 24 + bottomInset,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.badge_outlined,
                    color: Color(0xFF2563EB),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find Student by Unique ID',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'Strict ID lookup (e.g. MP-84920)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textCapitalization: TextCapitalization.characters,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Enter exact Student ID (e.g. MP-84920)...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _isLoading ? null : _performSearch,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C1618)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF7F1D1D)
                        : const Color(0xFFFECACA),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFFDC2626),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_result != null)
              _buildResultCard(_result!, isDark, theme)
            else if (!_hasSearched)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.fingerprint_rounded,
                      size: 48,
                      color: isDark
                          ? const Color(0xFF475569)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Unique Student Codes protect cohort identity.\nAsk a classmate for their MP code to view profile.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(
    StudentSearchResult student,
    bool isDark,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: student.verifiedBadge
                        ? const Color(0xFF2563EB)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundImage:
                      student.avatarUrl != null && student.avatarUrl!.isNotEmpty
                      ? NetworkImage(student.avatarUrl!)
                      : null,
                  backgroundColor: const Color(0xFF2563EB)
                      .withValues(alpha: 0.15),
                  child: student.avatarUrl == null || student.avatarUrl!.isEmpty
                      ? Text(
                          student.initials,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2563EB),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            student.fullName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (student.verifiedBadge) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            color: Color(0xFF2563EB),
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: student.studentCode),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Student ID copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  student.studentCode,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.copy,
                                  size: 12,
                                  color: Color(0xFF2563EB),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildRoleChip(student.appRole, isDark),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Study Points',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.stars_rounded,
                          size: 16,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${student.totalPoints} pts',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This Week',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          size: 16,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${student.weeklyPoints} pts',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isFollowLoading
                      ? null
                      : () => _toggleFollow(student),
                  icon: _isFollowLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isFollowing
                              ? Icons.check_circle_outline
                              : Icons.person_add_outlined,
                          size: 18,
                        ),
                  label: Text(_isFollowing ? 'Following' : 'Follow'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/profile?userId=${student.id}');
                  },
                  icon: const Icon(Icons.account_circle_outlined, size: 18),
                  label: const Text('View Profile'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleChip(String appRole, bool isDark) {
    Color bg;
    Color fg;
    String label;

    switch (appRole) {
      case 'owner':
        bg = const Color(0xFF7C3AED).withValues(alpha: 0.15);
        fg = const Color(0xFF8B5CF6);
        label = '🛡️ FOUNDER';
        break;
      case 'core_team':
        bg = const Color(0xFF0284C7).withValues(alpha: 0.15);
        fg = const Color(0xFF0EA5E9);
        label = '⭐ TEAM';
        break;
      case 'scholar':
        bg = const Color(0xFFD97706).withValues(alpha: 0.15);
        fg = const Color(0xFFF59E0B);
        label = '🎓 SCHOLAR';
        break;
      default:
        bg = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
        fg = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
        label = 'ASPIRANT';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
