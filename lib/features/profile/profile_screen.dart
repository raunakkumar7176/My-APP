import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/models/profile.dart';
import '../../core/services/auth_service.dart';
import 'state/profile_controller.dart';
import 'widgets/profile_avatar.dart';

/// Production Profile screen: view/edit profile fields, profile photo
/// upload (gallery/camera) with a full-screen zoomable viewer, and photo
/// removal — all against the existing `profiles` table and the new
/// `avatars` Storage bucket. Reached from Settings → Account and the
/// bottom-nav Profile tab's "Edit Profile" tile via the existing `/profile`
/// route (unchanged).
final class ProfileScreen extends StatefulWidget {
  const ProfileScreen({this.controller, this.currentUserEmail, super.key});

  /// Injection point for tests; production constructs its own.
  final ProfileController? controller;

  /// Injection point for tests — production defaults to the real
  /// authenticated user's email via [AuthService]; `AuthService.currentUser`
  /// touches the live Supabase client, which isn't available in widget
  /// tests (no fake Supabase client exists in this project's test infra).
  final String? Function()? currentUserEmail;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _c;
  late final bool _ownsController;

  late TextEditingController _fullNameController;
  late TextEditingController _bioController;
  late TextEditingController _mobileController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _c = widget.controller ?? ProfileController();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  String? _currentEmail() =>
      (widget.currentUserEmail ?? (() => AuthService.currentUser?.email))();

  void _seedControllersFromProfile(Profile profile) {
    _fullNameController.text = profile.fullName;
    _bioController.text = profile.bio;
    _mobileController.text = profile.mobile;
  }

  void _startEditing() {
    final profile = _c.profile;
    if (profile == null) return;
    _seedControllersFromProfile(profile);
    _c.startEditing();
  }

  void _cancelEditing() {
    final profile = _c.profile;
    if (profile != null) _seedControllersFromProfile(profile); // restore
    _c.cancelEditing();
  }

  Future<void> _handleSave() async {
    final ok = await _c.save(
      fullName: _fullNameController.text,
      bio: _bioController.text,
      mobile: _mobileController.text,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          if (_c.loadState == ProfileLoadState.loaded && !_c.isEditing)
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
    return RefreshIndicator(
      onRefresh: _c.load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ProfileAvatar(
                    initials: profile.initials,
                    avatarUrl: profile.avatarUrl,
                    radius: 56,
                    busy: _c.isAvatarBusy,
                    onTap: _openViewer,
                    onEditTap: _openPhotoActions,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    profile.displayName,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (profile.studentCode != null) ...[
                  const SizedBox(height: 2),
                  Center(
                    child: Text(
                      profile.studentCode!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (_c.isEditing)
                  _buildEditCard(profile)
                else
                  _buildViewCard(profile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewCard(Profile profile) {
    return Card(
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

  Widget _buildEditCard(Profile profile) {
    return Card(
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
            if (_c.saveError != null) ...[
              const SizedBox(height: 8),
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
            const SizedBox(height: 16),
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
