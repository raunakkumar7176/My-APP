import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/extracted_content.dart';
import '../models/question_draft.dart';
import '../state/document_upload_controller.dart';
import '../widgets/question_editor.dart';

/// Full-screen flow for uploading a document, extracting content,
/// detecting questions, reviewing them, and feeding them back to the
/// test creation wizard.
///
/// Returns a List of QuestionDraft via context.pop() when the user confirms.
class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({this.groupId, this.controller, super.key});

  final String? groupId;

  /// Injection point for tests; production constructs its own.
  final DocumentUploadController? controller;

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  late final DocumentUploadController _c;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _c = widget.controller ?? DocumentUploadController(groupId: widget.groupId);
    _c.addListener(_onChanged);
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_ownsController) _c.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _pickAndParse() async {
    await _c.pickUploadAndParse();
    if (_c.state == DocumentFlowState.parsed) {
      _c.startReview();
    } else if (_c.errorMessage != null) {
      _snack(_c.errorMessage!, error: true);
    }
  }

  /// Phase 2/3: "How do you want to add it? Take Photos / Choose File" —
  /// camera converges into the exact same parse → detect → review pipeline
  /// as a picked file (Phase 1/26), just via [DocumentUploadController.
  /// parseImages] instead of [pickUploadAndParse].
  Future<void> _pickImageAndParse() async {
    await _c.pickImageUploadAndParse();
    if (_c.state == DocumentFlowState.parsed) {
      _c.startReview();
    } else if (_c.errorMessage != null) {
      _snack(_c.errorMessage!, error: true);
    }
  }

  Future<void> _removeFile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this file?'),
        content: const Text(
          'This permanently deletes the uploaded file from storage. '
          'This cannot be undone.',
        ),
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
    if (confirmed != true) return;
    await _c.deleteCurrentDocument();
    if (_c.errorMessage != null) {
      _snack(_c.errorMessage!, error: true);
    } else {
      _snack('File removed.');
    }
  }

  Future<void> _takePhotos() async {
    final pages = await context.push<List<Uint8List>>(
      '/tests/create/camera-capture',
    );
    if (pages == null || pages.isEmpty) return;
    await _c.parseImages(pages);
    if (_c.state == DocumentFlowState.parsed) {
      _c.startReview();
    } else if (_c.errorMessage != null) {
      _snack(_c.errorMessage!, error: true);
    }
  }

  Future<void> _addManualQuestion() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: QuestionEditor(
          onSave: (draft) {
            Navigator.of(ctx).pop();
            _c.addManualQuestion(draft);
          },
        ),
      ),
    );
  }

  Future<void> _confirmAndReturn() async {
    final errors = _c.validateSelected();
    if (errors.isNotEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber,
            color: AppColors.error,
            size: 48,
          ),
          title: const Text('Validation Issues'),
          content: SingleChildScrollView(child: Text(errors.join('\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final drafts = _c.readyDrafts;
    if (drafts.isEmpty) {
      _snack('No questions selected.', error: true);
      return;
    }

    if (_c.saveToQuestionBank) {
      final saveResult = await _c.saveSelectedToQuestionBank();
      if (saveResult != null && mounted) {
        _snack(
          'Saved ${saveResult.savedCount} to Question Bank'
          '${saveResult.skippedDuplicateCount > 0 ? " (${saveResult.skippedDuplicateCount} duplicates skipped)" : ""}',
        );
      }
    }

    await _c.purgePostProcessing();
    if (mounted) context.pop(drafts);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _c.purgeOnCancellation();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Smart Document & AI Intake'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              await _c.purgeOnCancellation();
              if (context.mounted) context.pop();
            },
          ),
        ),
        body: _buildBody(theme),
        bottomNavigationBar: _buildBottomBar(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_c.state) {
      case DocumentFlowState.idle:
        return _buildIdleState(theme);
      case DocumentFlowState.picking:
      case DocumentFlowState.validating:
      case DocumentFlowState.uploading:
      case DocumentFlowState.parsing:
      case DocumentFlowState.deleting:
        return _buildLoadingState(theme);
      case DocumentFlowState.uploaded:
      case DocumentFlowState.parsed:
      case DocumentFlowState.reviewing:
        return _buildReviewState(theme);
      case DocumentFlowState.success:
        return _buildSuccessState(theme);
      case DocumentFlowState.error:
        return _buildErrorState(theme);
      case DocumentFlowState.creating:
        return _buildLoadingState(theme);
    }
  }

  Widget _buildIdleState(ThemeData theme) {
    // More format chips + a third action button than this screen started
    // with means the idle content no longer reliably fits an unscrolled
    // Column on shorter screens — scrollable, same as every other step in
    // this flow, rather than risking a silent overflow on small devices.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.upload_file_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 24),
            Text(
              'How do you want to add it?',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Take photos of the pages, choose a PDF, Word, or image file, '
              'or pick a photo from your gallery.\n'
              'Questions will be detected and you can review them before adding to your test.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _FormatChips(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('doc_import_take_photos'),
                onPressed: _takePhotos,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take Photos'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('doc_import_choose_file'),
                onPressed: _pickAndParse,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Choose File'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('doc_import_choose_image'),
                onPressed: _pickImageAndParse,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Choose Image'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    final message = switch (_c.state) {
      DocumentFlowState.picking => 'Selecting file…',
      DocumentFlowState.validating => 'Validating file…',
      DocumentFlowState.uploading => 'Uploading file…',
      DocumentFlowState.parsing => 'Parsing document and detecting questions…',
      DocumentFlowState.creating => 'Creating questions…',
      DocumentFlowState.deleting => 'Removing file…',
      _ => 'Processing…',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              message,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a moment for large files.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editQuestion(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: QuestionEditor(
          initial: _c.draftForQuestion(index),
          onSave: (draft) {
            Navigator.of(ctx).pop();
            _c.updateQuestionDraft(index, draft);
          },
        ),
      ),
    );
  }

  Widget _buildReviewState(ThemeData theme) {
    final questions = _c.detectedQuestions;
    final selected = _c.selectedIndices;
    final invalidCount = [
      for (var i = 0; i < questions.length; i++) _c.draftForQuestion(i),
    ].where((d) => !d.isValid).length;

    if (questions.isEmpty) {
      final format = _c.extractedContent?.sourceFormat;
      final isCamera = format == DocumentFormat.camera;
      final isImage = format == DocumentFormat.image;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: theme.colorScheme.error.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                'No questions detected',
                key: const Key('doc_import_none_detected'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                (isCamera || isImage)
                    // Honest: this build has no OCR, so photos/images never
                    // auto-detect anything — see the implementation report.
                    ? 'This app can\'t read text from photos yet. Add the '
                          'questions from your pages below.'
                    : 'The document was parsed but no structured questions '
                          'were found. Try a document with clearly formatted '
                          'questions and options (A/B/C/D), or add them below.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('doc_import_add_manual_empty'),
                onPressed: _addManualQuestion,
                icon: const Icon(Icons.add),
                label: const Text('Add Question'),
              ),
              if (_c.uploadedDoc != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('doc_import_remove_file_empty'),
                  onPressed: _removeFile,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Remove uploaded file'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Header bar.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${selected.length} of ${questions.length} selected',
                      key: const Key('doc_import_selection_count'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    key: const Key('doc_import_add_manual'),
                    tooltip: 'Add Question',
                    onPressed: _addManualQuestion,
                    icon: const Icon(Icons.add),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (_c.uploadedDoc != null)
                    IconButton(
                      key: const Key('doc_import_remove_file'),
                      tooltip: 'Remove uploaded file',
                      onPressed: _removeFile,
                      icon: const Icon(Icons.delete_forever_outlined),
                      visualDensity: VisualDensity.compact,
                    ),
                  TextButton(
                    onPressed: _c.selectAll,
                    child: const Text('Select All'),
                  ),
                  TextButton(
                    onPressed: _c.deselectAll,
                    child: const Text('None'),
                  ),
                ],
              ),
              if (invalidCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$invalidCount question${invalidCount == 1 ? '' : 's'} need attention — '
                          'tap Edit to fix (e.g. set the correct answer, the document never sets one automatically).',
                          key: const Key('doc_import_invalid_notice'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Content preview.
        if (_c.extractedContent != null)
          ExpansionTile(
            title: Text(
              'Document Content (${_c.extractedContent!.blockCount} blocks)',
              style: theme.textTheme.bodySmall,
            ),
            children: [
              Container(
                height: 200,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: ListView.builder(
                  itemCount: _c.extractedContent!.blocks.length,
                  itemBuilder: (ctx, i) {
                    final block = _c.extractedContent!.blocks[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${block.sourceLocation}: ${block.text}',
                        style: TextStyle(
                          fontSize: 11,
                          color: block.isQuestionLike
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                          fontWeight: block.isQuestionLike
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        // Questions list — drag the handle to reorder before import.
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: questions.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              _c.reorderQuestion(oldIndex, newIndex);
            },
            itemBuilder: (ctx, i) => _QuestionReviewCard(
              key: ValueKey('doc_import_q_$i'),
              index: i,
              question: questions[i],
              isSelected: selected.contains(i),
              draft: _c.draftForQuestion(i),
              onToggle: () => _c.toggleSelection(i),
              onEdit: () => _editQuestion(i),
              onRemove: () => _c.removeQuestion(i),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 64),
          const SizedBox(height: 16),
          Text(
            '${_c.selectedCount} questions added',
            style: theme.textTheme.titleLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _c.errorMessage ?? 'Something went wrong',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('doc_import_retry'),
              onPressed: _c.reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildBottomBar(ThemeData theme) {
    if (_c.state != DocumentFlowState.reviewing) return null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _c.saveToQuestionBank,
              onChanged: (val) => _c.setSaveToQuestionBank(val ?? false),
              title: Text(
                'Save selected to Question Bank / My Study',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => _c.reset(),
                  child: const Text('Start Over'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _c.selectedCount > 0 ? _confirmAndReturn : null,
                  child: Text(
                    'Add ${_c.selectedCount} Question${_c.selectedCount == 1 ? '' : 's'}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chips showing supported file formats.
class _FormatChips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _chip(theme, Icons.picture_as_pdf, 'PDF'),
        _chip(theme, Icons.description, 'DOC'),
        _chip(theme, Icons.description, 'DOCX'),
        _chip(theme, Icons.text_snippet_outlined, 'TXT'),
        _chip(theme, Icons.table_chart_outlined, 'XLSX'),
        _chip(theme, Icons.image_outlined, 'JPG'),
        _chip(theme, Icons.image_outlined, 'PNG'),
      ],
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    );
  }
}

/// A single question card in the review list. Shows the *current* draft
/// (edits applied on top of what was detected), its source location, and a
/// validity state — detection never sets a correct option (Phase 4: no
/// guessing), so every freshly-detected question starts "Needs review" until
/// the creator opens Edit and picks one.
class _QuestionReviewCard extends StatelessWidget {
  const _QuestionReviewCard({
    super.key,
    required this.index,
    required this.question,
    required this.isSelected,
    required this.draft,
    required this.onToggle,
    required this.onEdit,
    required this.onRemove,
  });

  final int index;
  final DetectedQuestion question;
  final bool isSelected;
  final QuestionDraft draft;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = draft.isValid;
    return Card(
      key: Key('doc_import_card_$index'),
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      shape: valid
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.warning.withValues(alpha: 0.6)),
            ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.drag_handle, size: 18),
                    ),
                  ),
                  Checkbox(
                    key: Key('doc_import_select_$index'),
                    value: isSelected,
                    onChanged: (_) => onToggle(),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Q${index + 1}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSourceBadge(theme),
                      ],
                    ),
                  ),
                  if (question.sourceLocation.isNotEmpty)
                    Text(
                      question.sourceLocation,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  IconButton(
                    key: Key('doc_import_edit_$index'),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    key: Key('doc_import_remove_$index'),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Remove',
                    onPressed: onRemove,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                draft.questionText.isEmpty
                    ? question.questionText
                    : draft.questionText,
                style: theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (draft.options.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < draft.options.length; i++)
                      Chip(
                        label: Text(
                          '${String.fromCharCode(65 + i)}. ${draft.options[i].text}',
                          style: theme.textTheme.bodySmall,
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: i == draft.correctOptionIndex
                            ? AppColors.success.withValues(alpha: 0.25)
                            : theme.colorScheme.surfaceContainerHighest,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    valid ? Icons.check_circle : Icons.error_outline,
                    size: 14,
                    color: valid ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    valid ? 'Ready' : _invalidReason(draft),
                    key: Key('doc_import_status_$index'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: valid ? AppColors.success : AppColors.warning,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${draft.marks} mark${draft.marks == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(ThemeData theme) {
    final isAi = draft.source == 'ai';
    final badgeColor = isAi ? Colors.purple : Colors.blue.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        isAi ? 'AI-GENERATED' : 'EXTRACTED',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: badgeColor,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  static String _invalidReason(QuestionDraft d) {
    if (d.questionText.trim().isEmpty) return 'Empty question text';
    if (!d.hasValidOptions) {
      return 'Needs ${QuestionDraft.minOptions} filled options '
          '(has ${d.options.where((o) => o.text.trim().isNotEmpty).length})';
    }
    if (!d.hasCorrectOption) return 'No correct answer set — tap Edit';
    return 'Needs review';
  }
}
