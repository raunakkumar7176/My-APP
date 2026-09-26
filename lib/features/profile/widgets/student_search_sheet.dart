import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/gamification_service.dart';

/// Modal bottom sheet that enables searching for any student by their
/// exact Unique Student ID (e.g., MP-84920).
class StudentSearchSheet extends StatefulWidget {
  const StudentSearchSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const StudentSearchSheet(),
    );
  }

  @override
  State<StudentSearchSheet> createState() => _StudentSearchSheetState();
}

class _StudentSearchSheetState extends State<StudentSearchSheet> {
  final _searchController = TextEditingController();
  bool _isLoading = false;
  StudentSearchResult? _result;
  String? _errorMessage;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasSearched = true;
    });

    try {
      final res = await GamificationService.searchStudentByCode(query);
      if (!mounted) return;
      setState(() {
        _result = res;
        _isLoading = false;
        if (res == null) {
          _errorMessage =
              'No student found with ID "$query". Please check and try again.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Search failed. Please try again.';
        _isLoading = false;
      });
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
                        'Find Student by ID',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'Enter exact Unique Student Code (e.g. MP-84920)',
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
                      hintText: 'e.g. MP-84920',
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
                      Icons.person_search_outlined,
                      size: 48,
                      color: isDark
                          ? const Color(0xFF475569)
                          : const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Search any peer across groups using their unique student ID.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF2563EB),
                backgroundImage: student.avatarUrl != null
                    ? NetworkImage(student.avatarUrl!)
                    : null,
                child: student.avatarUrl == null
                    ? Text(
                        student.fullName.isNotEmpty
                            ? student.fullName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.fullName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: student.studentCode),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Student ID copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              student.studentCode,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2563EB),
                                letterSpacing: 0.5,
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Points row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
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
                      Row(
                        children: [
                          const Icon(
                            Icons.stars_rounded,
                            color: Color(0xFFF59E0B),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Total Points',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${student.totalPoints} pts',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
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
                      Row(
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: Color(0xFF10B981),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'This Week',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${student.weeklyPoints} pts',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (student.bio != null && student.bio!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              student.bio!,
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
          if (student.examTargets.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Dream Goals / Targets:',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFFCBD5E1)
                    : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: student.examTargets.map((target) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    target,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
