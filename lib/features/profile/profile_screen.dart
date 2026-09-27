import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/models/profile.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/profile_service.dart';
import '../../core/services/supabase_service.dart';
import '../community/widgets/unique_id_search_sheet.dart';
import 'domain/age_calculator.dart';
import 'domain/social_platform.dart';
import 'state/profile_controller.dart';
import 'widgets/profile_avatar.dart';

/// Production Profile screen: view/edit profile fields, dynamic age calculator,
/// verified blue-tick badge desk, social media link launch, and student portfolio.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    this.controller,
    this.currentUserEmail,
    this.userId,
    this.initialProfile,
    super.key,
  });

  /// Injection point for tests; production constructs its own.
  final ProfileController? controller;

  /// Injection point for tests — production defaults to the real
  /// authenticated user's email via [AuthService].
  final String? Function()? currentUserEmail;

  /// Target user ID if viewing another student's profile.
  final String? userId;

  /// Optional initial profile data when navigating directly (e.g. Founder profile).
  final Profile? initialProfile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _c;
  late final bool _ownsController;

  late TextEditingController _fullNameController;
  late TextEditingController _bioController;
  late TextEditingController _mobileController;
  DateTime? _selectedDob;

  bool _isFollowing = false;
  bool _isFollowLoading = false;
  bool _isApplyingVerification = false;

  bool get _isViewingOther {
    if (_c.isViewingOther) return true;
    if (widget.userId == null || widget.userId!.isEmpty) return false;
    if (!SupabaseService.isInitialized) return false;
    try {
      final currentUid = AuthService.currentUser?.id;
      return widget.userId != currentUid;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _c =
        widget.controller ??
        ProfileController(
          targetUserId: widget.userId,
          initialProfile: widget.initialProfile,
        );
    _fullNameController = TextEditingController();
    _bioController = TextEditingController();
    _mobileController = TextEditingController();
    _c.addListener(_onChanged);
    _c.load();
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_ownsController) _c.dispose();
    _fullNameController.dispose();
    _bioController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _currentEmail() {
    if (widget.currentUserEmail != null) {
      return widget.currentUserEmail!();
    }
    if (!SupabaseService.isInitialized) return null;
    try {
      return AuthService.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  void _seedControllersFromProfile(Profile profile) {
    _fullNameController.text = profile.fullName;
    _bioController.text = profile.bio;
    _mobileController.text = profile.mobile;
    _selectedDob = profile.dateOfBirth;
  }

  void _startEditing() {
    final profile = _c.profile;
    if (profile == null) return;
    _seedControllersFromProfile(profile);
    _c.startEditing();
  }

  void _cancelEditing() {
    final profile = _c.profile;
    if (profile != null) _seedControllersFromProfile(profile);
    _c.cancelEditing();
  }

  Future<void> _handleSave() async {
    final ok = await _c.save(
      fullName: _fullNameController.text,
      bio: _bioController.text,
      mobile: _mobileController.text,
      dateOfBirth: _selectedDob,
    );
    if (!mounted) return;
    if (ok) {
      _snack('Profile updated successfully.');
    }
  }

  Future<void> _openViewer() async {
    final profile = _c.profile;
    final url = profile?.avatarUrl;
    final initials = profile?.initials ?? '?';
    await context.push(
      '/profile/avatar'
      '?url=${Uri.encodeComponent(url ?? '')}'
      '&initials=${Uri.encodeComponent(initials)}',
    );
  }

  Future<void> _openPhotoActions() async {
    final hasPhoto = _c.profile?.avatarUrl != null;
    final choice = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('profile_photo_action_gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(ctx).pop(_PhotoAction.gallery),
            ),
            ListTile(
              key: const Key('profile_photo_action_camera'),
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.of(ctx).pop(_PhotoAction.camera),
            ),
            if (hasPhoto)
              ListTile(
                key: const Key('profile_photo_action_remove'),
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () => Navigator.of(ctx).pop(_PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _PhotoAction.gallery:
        await _pickAndUpload(_c.pickAvatarFromGallery);
      case _PhotoAction.camera:
        await _pickAndUpload(_c.pickAvatarFromCamera);
      case _PhotoAction.remove:
        await _removePhoto();
    }
  }

  Future<void> _pickAndUpload(Future<Uint8List?> Function() pick) async {
    final bytes = await pick();
    if (!mounted) return;
    if (bytes == null) {
      if (_c.avatarError != null) _snack(_c.avatarError!, error: true);
      return;
    }
    final ok = await _c.uploadAvatar(bytes);
    if (!mounted) return;
    if (ok) {
      _snack('Profile photo updated.');
    } else if (_c.avatarError != null) {
      _snack(_c.avatarError!, error: true);
    }
  }

  Future<void> _removePhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove profile photo?'),
        content: const Text('You can add a new one anytime.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await _c.deleteAvatar();
    if (!mounted) return;
    if (ok) {
      _snack('Profile photo removed.');
    } else if (_c.avatarError != null) {
      _snack(_c.avatarError!, error: true);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initialDate = _selectedDob ?? DateTime(now.year - 18, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1960),
      lastDate: now,
      helpText: 'Select Date of Birth',
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDob = picked;
      });
    }
  }

  Future<void> _applyForBlueTick() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text('Apply for Blue Tick'),
          ],
        ),
        content: const Text(
          'Your profile and score will be submitted to the Founder Review Desk. '
          'Applicants with 1000+ points and verified integrity receive the scholar badge.',
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
            child: const Text('Submit Application'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isApplyingVerification = true);
    try {
      await ProfileService.applyForBlueTick();
      if (!mounted) return;
      _snack(
        'Verification request submitted! Our team will review within 24-48 hours.',
      );
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceAll('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _isApplyingVerification = false);
    }
  }

  Future<void> _launchSocialUrl(String url) async {
    var formatted = url.trim();
    if (formatted.isEmpty) return;
    if (!formatted.startsWith('http://') && !formatted.startsWith('https://')) {
      formatted = 'https://$formatted';
    }
    final uri = Uri.tryParse(formatted);
    if (uri == null) {
      _snack('Invalid link URL', error: true);
      return;
    }
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _snack('Could not open link: $url', error: true);
      }
    } catch (e) {
      if (mounted) _snack('Could not launch: $url', error: true);
    }
  }

  void _openSocialLinksEditor(Profile profile) {
    final items = <_SocialLinkItem>[];
    for (final entry in profile.socialLinks.entries) {
      final platform =
          SocialPlatform.fromKey(entry.key) ?? SocialPlatform.website;
      items.add(_SocialLinkItem(platform: platform, initialValue: entry.value));
    }
    if (items.isEmpty) {
      items.add(
        _SocialLinkItem(platform: SocialPlatform.linkedin, initialValue: ''),
      );
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.share_rounded, size: 20, color: Color(0xFF2563EB)),
                  SizedBox(width: 8),
                  Text('Social Media Handles'),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select a platform and enter your handle or profile URL.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...items.asMap().entries.map((indexed) {
                        final index = indexed.key;
                        final item = indexed.value;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
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
                              Row(
                                children: [
                                  DropdownButton<SocialPlatform>(
                                    value: item.platform,
                                    underline: const SizedBox.shrink(),
                                    borderRadius: BorderRadius.circular(10),
                                    onChanged: (newPlat) {
                                      if (newPlat != null) {
                                        setDialogState(() {
                                          item.platform = newPlat;
                                        });
                                      }
                                    },
                                    items: SocialPlatform.values.map((p) {
                                      return DropdownMenuItem<SocialPlatform>(
                                        value: p,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              p.icon,
                                              color: p.color,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              p.displayName,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                    tooltip: 'Remove',
                                    onPressed: () {
                                      setDialogState(() {
                                        item.dispose();
                                        items.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: item.controller,
                                decoration: InputDecoration(
                                  hintText: item.platform.hint,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (items.length < SocialPlatform.values.length)
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                final used = items
                                    .map((i) => i.platform)
                                    .toSet();
                                final next = SocialPlatform.values.firstWhere(
                                  (p) => !used.contains(p),
                                  orElse: () => SocialPlatform.website,
                                );
                                items.add(
                                  _SocialLinkItem(
                                    platform: next,
                                    initialValue: '',
                                  ),
                                );
                              });
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('+ Add Social Link'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    for (final item in items) {
                      item.dispose();
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final updated = <String, String>{};
                    for (final item in items) {
                      final raw = item.controller.text.trim();
                      if (raw.isNotEmpty) {
                        final norm = SocialPlatform.normalizeUrl(
                          item.platform,
                          raw,
                        );
                        updated[item.platform.key] = norm;
                      }
                      item.dispose();
                    }
                    Navigator.of(ctx).pop();
                    final ok = await _c.saveSocialLinks(updated);
                    if (ok) {
                      _snack('Social handles saved.');
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleFollow(Profile profile) async {
    setState(() => _isFollowLoading = true);
    try {
      if (_isFollowing) {
        await ProfileService.unfollowUser(profile.id);
        if (mounted) setState(() => _isFollowing = false);
        _snack('Unfollowed ${profile.displayName}.');
      } else {
        await ProfileService.followUser(profile.id);
        if (mounted) setState(() => _isFollowing = true);
        _snack('Following ${profile.displayName}!');
      }
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceAll('Exception: ', ''), error: true);
      }
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isViewingOther ? 'Student Profile' : 'My Portfolio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search Student by ID',
            onPressed: () => UniqueIdSearchSheet.show(context),
          ),
          if (!_isViewingOther &&
              _c.loadState == ProfileLoadState.loaded &&
              !_c.isEditing)
            IconButton(
              key: const Key('profile_edit_button'),
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _startEditing,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_c.loadState) {
      case ProfileLoadState.loading:
        return const Center(child: CircularProgressIndicator());

      case ProfileLoadState.error:
        return _ErrorState(
          message: _c.loadError ?? 'Something went wrong.',
          onRetry: _c.load,
        );

      case ProfileLoadState.empty:
        return _EmptyState(onRetry: _c.load);

      case ProfileLoadState.loaded:
        final profile = _c.profile;
        if (profile == null) {
          return _EmptyState(onRetry: _c.load);
        }
        return _buildLoaded(profile);
    }
  }

  Widget _buildLoaded(Profile profile) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ageString = AgeCalculator.calculatePreciseAge(profile.dateOfBirth);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 600;
        final hPadding = isSmallScreen ? 16.0 : 24.0;
        final vPadding = isSmallScreen ? 16.0 : 24.0;

        return RefreshIndicator(
          onRefresh: _c.load,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: hPadding,
              vertical: vPadding,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Header Identity & Avatar Ring
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: profile.appRole == AppRole.owner
                                ? const Color(0xFFF59E0B)
                                : profile.verifiedBadge
                                ? const Color(0xFF2563EB)
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: ProfileAvatar(
                          initials: profile.initials,
                          avatarUrl: profile.avatarUrl,
                          radius: 46,
                          busy: _c.isAvatarBusy,
                          onTap: _openViewer,
                          onEditTap: _isViewingOther ? null : _openPhotoActions,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Name & Verified Tick (Golden for Founder, Blue for Scholar)
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              profile.displayName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.2,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (profile.appRole == AppRole.owner) ...[
                            const SizedBox(width: 6),
                            const Tooltip(
                              message: '👑 Official Founder',
                              child: Icon(
                                Icons.verified_rounded,
                                color: Color(0xFFF59E0B),
                                size: 20,
                              ),
                            ),
                          ] else if (profile.verifiedBadge) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified_rounded,
                              color: Color(0xFF2563EB),
                              size: 20,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Role Chip & Dynamic Age Badge
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildRoleBadge(
                            profile.appRole,
                            profile.verifiedBadge,
                            isDark,
                          ),
                          if (ageString != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                '🎂 Age: $ageString',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFFCBD5E1)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Unique Student ID Pill (Copyable)
                    if (profile.studentCode != null)
                      Center(
                        child: InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: profile.studentCode!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Student ID copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  profile.studentCode!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.copy,
                                  size: 13,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // 2. Metrics & Follow Strip
                    _buildMetricsStrip(profile, isDark, theme),

                    // Founder Credentials & Achievements Card (if Founder)
                    if (profile.appRole == AppRole.owner) ...[
                      const SizedBox(height: 20),
                      _buildFounderCredentialsCard(isDark),
                    ],

                    const SizedBox(height: 20),

                    // 3. Social Media Handles Row / Card
                    _buildSocialRow(profile, isDark),

                    const SizedBox(height: 20),

                    // 4. Blue Tick Verification Card
                    if (!_isViewingOther)
                      _buildBlueTickVerificationCard(profile, isDark, theme),

                    const SizedBox(height: 20),

                    // 5. Main Card: View / Edit Form
                    if (_c.isEditing)
                      _buildEditCard(profile, isDark)
                    else
                      _buildViewCard(profile),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleBadge(AppRole role, bool isVerified, bool isDark) {
    String label;
    Color color;

    switch (role) {
      case AppRole.owner:
        label = '🛡️ FOUNDER';
        color = const Color(0xFF7C3AED);
        break;
      case AppRole.coreTeam:
        label = '⭐ CORE TEAM';
        color = const Color(0xFF0284C7);
        break;
      case AppRole.scholar:
        label = '⭐ SCHOLAR';
        color = const Color(0xFFD97706);
        break;
      case AppRole.aspirant:
        if (isVerified) {
          label = '⭐ SCHOLAR';
          color = const Color(0xFF2563EB);
        } else {
          label = '📚 ASPIRANT';
          color = const Color(0xFF64748B);
        }
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMetricsStrip(Profile profile, bool isDark, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildCounterItem(
                'Followers',
                '${profile.followersCount}',
                isDark,
              ),
              _buildVerticalDivider(isDark),
              _buildCounterItem(
                'Following',
                '${profile.followingCount}',
                isDark,
              ),
              _buildVerticalDivider(isDark),
              _buildCounterItem(
                'Study Points',
                '${profile.totalPoints}',
                isDark,
                isHighlight: true,
              ),
            ],
          ),
          if (_isViewingOther) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isFollowLoading
                    ? null
                    : () => _toggleFollow(profile),
                style: FilledButton.styleFrom(
                  backgroundColor: _isFollowing
                      ? const Color(0xFF475569)
                      : const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _isFollowLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isFollowing ? Icons.check : Icons.person_add,
                        size: 18,
                      ),
                label: Text(_isFollowing ? 'Following ✓' : '+ Follow'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCounterItem(
    String label,
    String value,
    bool isDark, {
    bool isHighlight = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isHighlight ? const Color(0xFFF59E0B) : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider(bool isDark) {
    return Container(
      width: 1,
      height: 28,
      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
    );
  }

  Widget _buildFounderCredentialsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF2E1065), const Color(0xFF1E1B4B)]
              : [const Color(0xFFF5F3FF), const Color(0xFFEDE9FE)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFF59E0B),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Founder & System Architect',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFFD97706),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Official App Creator & Academic Lead',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF475569),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x22F59E0B)),
          const SizedBox(height: 12),
          _buildFounderPill(
            icon: Icons.lightbulb_outline_rounded,
            title: 'Vision',
            description: 'Democratizing top-tier competitive exam preparation with synchronized peer study.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildFounderPill(
            icon: Icons.security_rounded,
            title: 'Invigilator & Integrity',
            description: 'Server-authoritative synchronized challenges, merit fairness & fraud prevention.',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildFounderPill(
            icon: Icons.school_rounded,
            title: 'Mentorship',
            description: 'Dedicated to empowering aspirants across UPSC, State PCS, SSC, and Banking exams.',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildFounderPill({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF7C3AED)),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFF334155),
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialRow(Profile profile, bool isDark) {
    final links = profile.socialLinks;
    final hasLinks = links.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.share_rounded,
                      size: 18,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF475569),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Social Handles & Links',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isViewingOther) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _openSocialLinksEditor(profile),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (!hasLinks)
            Text(
              _isViewingOther ? 'No social handles linked yet.' : 'Add your LinkedIn, YouTube, X, GitHub or portfolio links to connect with peers.',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8),
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: links.entries.map((entry) {
                final platform = SocialPlatform.fromKey(entry.key);
                final color = platform?.color ?? const Color(0xFF6366F1);
                final icon = platform?.icon ?? Icons.link_rounded;
                final label = platform?.displayName ?? entry.key;

                return InkWell(
                  onTap: () => _launchSocialUrl(entry.value),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.2 : 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: color.withValues(alpha: isDark ? 0.4 : 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: color),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : color,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_outward_rounded,
                          size: 11,
                          color: isDark
                              ? Colors.white70
                              : color.withValues(alpha: 0.8),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildBlueTickVerificationCard(
    Profile profile,
    bool isDark,
    ThemeData theme,
  ) {
    if (profile.verifiedBadge) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF2563EB).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_rounded,
              color: Color(0xFF2563EB),
              size: 32,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verified Scholar Profile',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your academic rank and study credentials are confirmed by My Preparation.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final current = profile.totalPoints;
    const requiredPoints = 1000;
    final progress = (current / requiredPoints).clamp(0.0, 1.0);
    final isEligible = current >= requiredPoints;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
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
              const Icon(
                Icons.verified_outlined,
                color: Color(0xFF2563EB),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Scholar Verification',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$current / $requiredPoints pts',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF2563EB),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isEligible
                ? 'Congratulations! You meet the 1000 study points milestone. Apply now for review.'
                : 'Earn ${requiredPoints - current} more points by solving practice sets and tests to unlock verification.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (isEligible && !_isApplyingVerification)
                  ? _applyForBlueTick
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _isApplyingVerification
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                isEligible ? 'Apply for Blue Tick' : 'Requires 1000 Points',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewCard(Profile profile) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF334155)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          _InfoTile(
            icon: Icons.person_outline,
            label: 'Full Name',
            value: profile.fullName.isEmpty ? '—' : profile.fullName,
          ),
          const Divider(height: 1),
          _InfoTile(
            icon: Icons.mail_outline,
            label: 'Email',
            value: _currentEmail() ?? '—',
          ),
          const Divider(height: 1),
          _InfoTile(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: profile.mobile.isEmpty ? 'Not set' : profile.mobile,
          ),
          const Divider(height: 1),
          _InfoTile(
            icon: Icons.info_outline,
            label: 'Bio',
            value: profile.bio.isEmpty ? 'Not set' : profile.bio,
          ),
          if (profile.dateOfBirth != null) ...[
            const Divider(height: 1),
            _InfoTile(
              icon: Icons.cake_outlined,
              label: 'Date of Birth',
              value: _formatDate(profile.dateOfBirth!),
            ),
          ],
          const Divider(height: 1),
          _InfoTile(
            icon: Icons.calendar_today_outlined,
            label: 'Member since',
            value: _formatDate(profile.createdAt),
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildEditCard(Profile profile, bool isDark) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('profile_edit_name'),
              controller: _fullNameController,
              textInputAction: TextInputAction.next,
              maxLength: ProfileValidators.nameMaxLength,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              enabled: !_c.isSaving,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('profile_edit_mobile'),
              controller: _mobileController,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.phone,
              maxLength: ProfileValidators.mobileMaxLength,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              enabled: !_c.isSaving,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('profile_edit_bio'),
              controller: _bioController,
              maxLines: 3,
              maxLength: ProfileValidators.bioMaxLength,
              decoration: const InputDecoration(
                labelText: 'Bio',
                prefixIcon: Icon(Icons.info_outline),
                alignLabelWithHint: true,
              ),
              enabled: !_c.isSaving,
            ),
            const SizedBox(height: 12),

            // Date of birth picker with micro-copy
            InkWell(
              onTap: _c.isSaving ? null : _pickDob,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of Birth',
                  prefixIcon: Icon(Icons.cake_outlined),
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedDob != null
                          ? _formatDate(_selectedDob!)
                          : 'Select your birthday',
                      style: TextStyle(
                        color: _selectedDob == null
                            ? Theme.of(context).hintColor
                            : null,
                      ),
                    ),
                    const Icon(Icons.calendar_month, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your date of birth is used to compute your exact age badge and will never be shared without your permission.',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),

            if (_c.saveError != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('profile_save_error'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _c.saveError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('profile_cancel_button'),
                    onPressed: _c.isSaving ? null : _cancelEditing,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('profile_save_button'),
                    onPressed: _c.isSaving ? null : _handleSave,
                    child: _c.isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

enum _PhotoAction { gallery, camera, remove }

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(value, style: theme.textTheme.bodyLarge),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            const Text('No profile found.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _SocialLinkItem {
  _SocialLinkItem({required this.platform, required String initialValue})
    : controller = TextEditingController(text: initialValue);

  SocialPlatform platform;
  final TextEditingController controller;

  void dispose() {
    controller.dispose();
  }
}
