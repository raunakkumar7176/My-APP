import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/services/gamification_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/supabase_service.dart';

/// Modal bottom sheet enabling Founder / Owner to promote students,
/// assign custom honor titles, grant VIP access, or award Verified Blue Ticks.
class UserPromotionModal extends StatefulWidget {
  const UserPromotionModal({
    super.key,
    this.initialStudentCode,
    this.onPromoted,
  });

  final String? initialStudentCode;
  final VoidCallback? onPromoted;

  /// Shows the promotion modal sheet.
  static Future<void> show(
    BuildContext context, {
    String? initialStudentCode,
    VoidCallback? onPromoted,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UserPromotionModal(
        initialStudentCode: initialStudentCode,
        onPromoted: onPromoted,
      ),
    );
  }

  @override
  State<UserPromotionModal> createState() => _UserPromotionModalState();
}

class _UserPromotionModalState extends State<UserPromotionModal> {
  late final TextEditingController _studentCodeController;
  late final TextEditingController _roleTitleController;

  String _selectedRole = 'core_team';
  bool _grantVip = true;
  bool _grantBlueTick = true;

  bool _isSubmitting = false;
  bool _isSearching = false;
  StudentSearchResult? _foundStudent;
  String? _lookupMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _studentCodeController = TextEditingController(
      text: widget.initialStudentCode ?? '',
    );
    _roleTitleController = TextEditingController();

    if (widget.initialStudentCode != null &&
        widget.initialStudentCode!.trim().isNotEmpty) {
      _lookupStudent(widget.initialStudentCode!.trim());
    }
  }

  @override
  void dispose() {
    _studentCodeController.dispose();
    _roleTitleController.dispose();
    super.dispose();
  }

  Future<void> _lookupStudent(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return;

    if (!SupabaseService.isInitialized) {
      return;
    }

    setState(() {
      _isSearching = true;
      _lookupMessage = null;
      _errorMessage = null;
    });

    try {
      final student = await GamificationService.searchStudentByCode(cleanCode);
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _foundStudent = student;
        if (student == null) {
          _lookupMessage = 'No student found with ID "$cleanCode".';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _lookupMessage = 'Could not verify student ID. You can still proceed.';
      });
    }
  }

  Future<void> _submitPromotion() async {
    final studentCode = _studentCodeController.text.trim().toUpperCase();
    if (studentCode.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a Student ID (e.g. MP-84920).';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final roleTitle = _roleTitleController.text.trim();
      final res = await ProfileService.promoteUser(
        studentCode: studentCode,
        newRole: _selectedRole,
        roleTitle: roleTitle.isNotEmpty ? roleTitle : null,
        grantVip: _grantVip,
        grantBlueTick: _grantBlueTick,
      );

      if (!mounted) return;

      final successMsg =
          res['message'] as String? ??
          'Successfully promoted $studentCode to ${_roleDisplayName(_selectedRole)}!';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMsg), backgroundColor: AppColors.success),
      );

      widget.onPromoted?.call();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceFirst(
          RegExp(r'^Exception:\s*'),
          '',
        );
      });
    }
  }

  String _roleDisplayName(String role) {
    switch (role) {
      case 'core_team':
        return 'Core Team';
      case 'scholar':
        return 'Scholar';
      case 'aspirant':
        return 'Aspirant';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
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

            // Modal Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.military_tech_rounded,
                      color: Color(0xFF7C3AED),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Promote Student Role',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Founder privilege to assign roles & blue ticks',
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
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Modal Content (Scrollable)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Student Code Input
                    Text(
                      'Target Student ID',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('promote_student_code_field'),
                      controller: _studentCodeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'e.g. MP-84920',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                key: const Key('promote_lookup_button'),
                                icon: const Icon(Icons.search_rounded),
                                tooltip: 'Lookup Student',
                                onPressed: () =>
                                    _lookupStudent(_studentCodeController.text),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: _lookupStudent,
                    ),

                    if (_lookupMessage != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _lookupMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _foundStudent != null
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ],

                    // Found Student Mini Preview Card
                    if (_foundStudent != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFF7C3AED),
                              backgroundImage:
                                  _foundStudent!.avatarUrl != null &&
                                      _foundStudent!.avatarUrl!.isNotEmpty
                                  ? NetworkImage(_foundStudent!.avatarUrl!)
                                  : null,
                              child:
                                  _foundStudent!.avatarUrl == null ||
                                      _foundStudent!.avatarUrl!.isEmpty
                                  ? Text(
                                      _foundStudent!.initials,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _foundStudent!.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_foundStudent!.verifiedBadge) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.verified_rounded,
                                          size: 14,
                                          color: Color(0xFF2563EB),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_foundStudent!.studentCode} • ${_foundStudent!.totalPoints} pts',
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
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Role Selection
                    Text(
                      'Select New Role',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildRoleSelector(isDark),

                    const SizedBox(height: 20),

                    // Custom Role Title
                    Text(
                      'Custom Role Title (Optional)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('promote_role_title_field'),
                      controller: _roleTitleController,
                      decoration: InputDecoration(
                        hintText:
                            'e.g. Senior Subject Mentor, Founding Scholar',
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Privileges Section
                    Text(
                      'Privileges & Badges',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          SwitchListTile(
                            key: const Key('promote_grant_vip_switch'),
                            value: _grantVip,
                            onChanged: (val) => setState(() => _grantVip = val),
                            title: const Row(
                              children: [
                                Icon(
                                  Icons.workspace_premium_rounded,
                                  size: 18,
                                  color: Color(0xFFD97706),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Grant VIP Access',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: const Text(
                              'Unlocks unrestricted cohort access & premium study tools',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            key: const Key('promote_grant_blue_tick_switch'),
                            value: _grantBlueTick,
                            onChanged: (val) =>
                                setState(() => _grantBlueTick = val),
                            title: const Row(
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: Color(0xFF2563EB),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Grant Verified Blue Tick',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: const Text(
                              'Awards verified scholar checkmark on profile and chat',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Error Message
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.error,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Sticky Bottom Submit Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('promote_submit_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _submitPromotion,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.military_tech_rounded, size: 20),
                  label: Text(
                    _isSubmitting
                        ? 'Promoting...'
                        : 'Promote & Grant Privileges',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelector(bool isDark) {
    final roles = [
      (
        key: 'core_team',
        label: 'Core Team',
        icon: Icons.shield_rounded,
        color: const Color(0xFF7C3AED),
        description: 'Staff & admin cohort powers',
      ),
      (
        key: 'scholar',
        label: 'Scholar',
        icon: Icons.stars_rounded,
        color: const Color(0xFF2563EB),
        description: 'Academic honor & elite tier',
      ),
      (
        key: 'aspirant',
        label: 'Aspirant',
        icon: Icons.school_rounded,
        color: const Color(0xFF10B981),
        description: 'Standard cohort student',
      ),
    ];

    return Column(
      children: roles.map((role) {
        final isSelected = _selectedRole == role.key;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isSelected
                ? role.color.withValues(alpha: isDark ? 0.2 : 0.1)
                : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected
                    ? role.color
                    : (isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0)),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _selectedRole = role.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(role.icon, color: role.color, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            role.label,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isSelected ? role.color : null,
                            ),
                          ),
                          Text(
                            role.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? role.color
                              : (isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8)),
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: role.color,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
