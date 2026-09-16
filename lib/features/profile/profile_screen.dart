import 'package:flutter/material.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/models/profile.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/profile_service.dart';

final class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _fullNameController;
  late TextEditingController _bioController;
  late TextEditingController _mobileController;
  late TextEditingController _timezoneController;
  late TextEditingController _examTargetsController;

  Profile? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController();
    _bioController = TextEditingController();
    _mobileController = TextEditingController();
    _timezoneController = TextEditingController();
    _examTargetsController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _bioController.dispose();
    _mobileController.dispose();
    _timezoneController.dispose();
    _examTargetsController.dispose();
    super.dispose();
  }

  void _loadProfile() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final existing = ProfileService.currentProfile;
    if (existing != null) {
      _setProfile(existing);
      return;
    }

    ProfileService.loadProfile().then((_) {
      if (mounted) {
        final profile = ProfileService.currentProfile;
        if (profile != null) {
          _setProfile(profile);
        } else {
          setState(() {
            _error = 'Profile not found.';
            _isLoading = false;
          });
        }
      }
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('AppError: ', '');
          _isLoading = false;
        });
      }
    });
  }

  void _setProfile(Profile profile) {
    _profile = profile;
    _fullNameController.text = profile.fullName;
    _bioController.text = profile.bio;
    _mobileController.text = profile.mobile;
    _timezoneController.text = profile.timezone;
    _examTargetsController.text = profile.examTargets.join(', ');
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_profile == null) return;

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    final examTargetsRaw = _examTargetsController.text.trim();
    final examTargets = examTargetsRaw.isEmpty
        ? <String>[]
        : examTargetsRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    try {
      await ProfileService.updateProfile(
        fullName: _fullNameController.text.trim(),
        bio: _bioController.text.trim(),
        mobile: _mobileController.text.trim(),
        timezone: _timezoneController.text.trim().isEmpty
            ? 'Asia/Kolkata'
            : _timezoneController.text.trim(),
        examTargets: examTargets,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _saveError = e.toString().replaceFirst('AppError: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primaryLight.withValues(alpha: 0.1),
                    child: Text(
                      _profile?.initials ?? '?',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_profile?.studentCode != null)
                  Center(
                    child: Text(
                      _profile!.studentCode!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    AuthService.currentUser?.email ?? '',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _fullNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                  enabled: !_isSaving,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bioController,
                  textInputAction: TextInputAction.next,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    prefixIcon: Icon(Icons.info_outline),
                    alignLabelWithHint: true,
                  ),
                  enabled: !_isSaving,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _mobileController,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  enabled: !_isSaving,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _timezoneController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Timezone',
                    prefixIcon: Icon(Icons.access_time),
                  ),
                  enabled: !_isSaving,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _examTargetsController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Exam Targets (comma-separated)',
                    prefixIcon: Icon(Icons.flag_outlined),
                    hintText: 'e.g. JEE, NEET, UPSC',
                  ),
                  enabled: !_isSaving,
                ),
                if (_saveError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _saveError!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save Profile',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                if (_profile?.createdAt != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Member since ${_formatDate(_profile!.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
