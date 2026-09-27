import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/errors/app_error.dart';
import '../services/feedback_service.dart';

const _feedbackTypes = [
  ('bug', '🐛 Report Bug'),
  ('feature_request', '💡 Suggestion'),
  ('content_error', '📚 Content Error'),
  ('general', '🌟 General'),
];

const _ratingLabels = ['Poor', 'Fair', 'Good', 'Very Good', 'Excellent'];

/// "Help & Feedback" dialog: category, star rating, message, optional
/// screenshot, and two ways to send it — a plain `mailto:` handoff, or an
/// in-app submission into `app_feedbacks` (migration 0067).
class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  String _type = 'bug';
  int _rating = 0;
  final _message = TextEditingController();
  Uint8List? _screenshot;
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot(bool fromCamera) async {
    try {
      final bytes = await FeedbackService.pickScreenshot(fromCamera: fromCamera);
      if (bytes != null && mounted) setState(() => _screenshot = bytes);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _showScreenshotSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickScreenshot(true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickScreenshot(false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendViaEmail() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await FeedbackService.launchSupportEmail(initialBody: _message.text.trim());
      if (mounted) setState(() => _submitted = true);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitInApp() async {
    if (_rating == 0) {
      setState(() => _error = 'Please choose a star rating.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await FeedbackService.submitInAppFeedback(
        feedbackType: _type,
        rating: _rating,
        message: _message.text,
        screenshotBytes: _screenshot,
      );
      if (mounted) setState(() => _submitted = true);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Help & Feedback'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: _submitted ? _buildSuccess(theme) : _buildForm(theme),
        ),
      ),
      actions: _submitted
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton.icon(
                key: const Key('feedback_email_btn'),
                onPressed: _submitting ? null : _sendViaEmail,
                icon: const Icon(Icons.email_outlined, size: 18),
                label: const Text('Send via Email'),
              ),
              FilledButton.icon(
                key: const Key('feedback_submit_btn'),
                onPressed: _submitting ? null : _submitInApp,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: const Text('Submit In-App'),
              ),
            ],
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Official support: ${FeedbackService.supportEmail}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in _feedbackTypes)
              ChoiceChip(
                key: Key('feedback_type_$value'),
                label: Text(label),
                selected: _type == value,
                onSelected: (_) => setState(() => _type = value),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                key: Key('feedback_star_$i'),
                onPressed: () => setState(() => _rating = i),
                icon: Icon(
                  i <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                  color: i <= _rating ? Colors.amber : theme.colorScheme.outline,
                  size: 28,
                ),
              ),
          ],
        ),
        if (_rating > 0)
          Center(
            child: Text(
              _ratingLabels[_rating - 1],
              style: theme.textTheme.labelMedium,
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('feedback_message_field'),
          controller: _message,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Message',
            hintText: 'Tell us what happened (minimum 10 characters)...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_screenshot == null)
          OutlinedButton.icon(
            key: const Key('feedback_add_screenshot_btn'),
            onPressed: _showScreenshotSourceSheet,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text('Attach Screenshot (optional)'),
          )
        else
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_screenshot!, height: 120, fit: BoxFit.cover, width: double.infinity),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: InkWell(
                  key: const Key('feedback_remove_screenshot_btn'),
                  onTap: () => setState(() => _screenshot = null),
                  child: const CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    return Container(
      key: const Key('feedback_success_banner'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration_outlined, size: 36),
          SizedBox(height: 8),
          Text(
            'Thank you! Our support team (${FeedbackService.supportEmail}) '
                'will review your note.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
