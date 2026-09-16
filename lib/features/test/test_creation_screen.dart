import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/errors/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/question.dart';
import '../../core/models/test.dart';
import '../../core/models/test_kind.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/question_service.dart';
import '../../core/services/test_service.dart';
import 'models/question_draft.dart';
import 'widgets/step_basic_details.dart';
import 'widgets/step_configuration.dart';
import 'widgets/step_questions.dart';
import 'widgets/step_review.dart';
import 'widgets/step_syllabus.dart';

class TestCreationScreen extends StatefulWidget {
  const TestCreationScreen({
    this.testId,
    super.key,
  });

  final String? testId;

  /// Default duration applied when the user picks a Self-family kind. The
  /// server always sets an attempt deadline from duration_sec (there is no
  /// "untimed" mode yet), so Practice gets a generous limit rather than none.
  static const practiceDefaultDurationSec = 3 * 60 * 60;
  static const quickDefaultDurationSec = 10 * 60;

  /// Quick Test target size. Stored in `settings.target_question_count` as
  /// metadata and shown as guidance in the Questions step; nothing on the
  /// server enforces it (the wizard has no question-count concept).
  static const quickTargetQuestionCount = 10;
  static const targetQuestionCountKey = 'target_question_count';

  /// Non-blocking hint for the Questions step, per Self-family kind.
  static String? questionsGuidance(String? testMode, TestKind kind) {
    if (testMode != 'self') return null;
    switch (kind) {
      case TestKind.quick:
        return 'Quick Test: aim for 5–$quickTargetQuestionCount questions '
            '(about ${quickDefaultDurationSec ~/ 60} minutes).';
      case TestKind.sectional:
        return 'Sectional Test: add questions for each subject/topic you '
            'select in the Syllabus step.';
      case TestKind.practice:
      case TestKind.self:
        return null;
    }
  }

  /// Persists [drafts] one by one via [create]. A draft is removed from
  /// [drafts] as soon as its create call succeeds, so if a later one fails
  /// (the error is rethrown) the caller can retry with only the unsaved
  /// drafts still in the list. [approve] (optional) is called with the new
  /// question id after each successful create; its failures are logged only.
  @visibleForTesting
  static Future<void> persistDraftQuestions(
    List<QuestionDraft> drafts, {
    required Future<String> Function(QuestionDraft draft) create,
    Future<void> Function(String questionId)? approve,
  }) async {
    final pending = List<QuestionDraft>.from(drafts);
    for (var i = 0; i < pending.length; i++) {
      final draft = pending[i];
      final String questionId;
      try {
        questionId = await create(draft);
        drafts.remove(draft);
        AppLogger.info('Question ${i + 1} created: $questionId');
      } catch (e) {
        AppLogger.error('Failed to create question ${i + 1}: $e');
        rethrow;
      }

      if (approve != null) {
        // The question is already persisted (and dropped from `drafts`), so
        // a failure here must not be swallowed: publishing would then be
        // rejected by the server with a less specific message. Surface it and
        // let the user approve from the Review step.
        try {
          await approve(questionId);
          AppLogger.info('Question ${i + 1} approved');
        } catch (e) {
          AppLogger.error('Failed to approve question ${i + 1}: $e');
          throw DataError(
            message: 'Question ${i + 1} was saved but could not be approved. '
                'Approve it from the Review step, then publish.',
          );
        }
      }
    }
  }

  /// Brings [server] in line with [local]: nodes in [local] but not [server]
  /// are passed to [add], nodes in [server] but not [local] to [remove].
  /// [server] is updated after each successful call, so a retry after a
  /// failure (rethrown) never re-submits the same node.
  @visibleForTesting
  static Future<void> persistSyllabusSelection({
    required List<String> local,
    required List<String> server,
    required Future<void> Function(String nodeId) add,
    required Future<void> Function(String nodeId) remove,
  }) async {
    for (final nodeId in List<String>.from(local)) {
      if (!server.contains(nodeId)) {
        try {
          await add(nodeId);
          server.add(nodeId);
          AppLogger.info('Syllabus node $nodeId added');
        } catch (e) {
          AppLogger.error('Failed to add syllabus $nodeId: $e');
          rethrow;
        }
      }
    }

    for (final nodeId in List<String>.from(server)) {
      if (!local.contains(nodeId)) {
        try {
          await remove(nodeId);
          server.remove(nodeId);
          AppLogger.info('Syllabus node $nodeId removed');
        } catch (e) {
          AppLogger.error('Failed to remove syllabus $nodeId: $e');
          rethrow;
        }
      }
    }
  }

  @override
  State<TestCreationScreen> createState() => _TestCreationScreenState();
}

class _TestCreationScreenState extends State<TestCreationScreen> {
  int _currentStep = 0;
  bool _isSaving = false;
  bool _isPublishing = false;
  bool _isLoadingDraft = false;
  String? _draftError;

  // Step 1 - Basic Details
  String _title = '';
  String _description = '';

  // Step 2 - Configuration
  int? _durationSec;
  double? _marksPerQuestion;
  double? _negativeMarks;
  String? _testMode;
  // Self-family kind (Practice / Quick / Sectional); stored in
  // settings.test_kind while test_mode stays 'self'.
  TestKind _testKind = TestKind.self;
  String? _groupId;
  DateTime? _startsAt;
  DateTime? _endsAt;
  int? _maxParticipants;
  bool _allowLateJoin = false;
  String? _accessCode;
  String? _joinCode;

  // Step 3 - Questions (local drafts)
  final List<QuestionDraft> _questions = [];

  // Step 3b - Questions from server (existing questions when editing)
  final List<Question> _serverQuestions = [];

  // Step 4 - Syllabus (local node IDs)
  final List<String> _syllabusNodeIds = [];

  // Step 4b - Syllabus from server (existing syllabus when editing)
  final List<String> _serverSyllabusNodeIds = [];

  // Edit mode: true when the test exists on the server — either opened via
  // /edit-test/:id, or created earlier in this same screen session.
  // `_loadedTest` is the authoritative persisted test for this session.
  bool get _isEditMode => widget.testId != null || _loadedTest != null;
  Test? _loadedTest;

  static const _stepTitles = [
    'Basic Details',
    'Configuration',
    'Questions',
    'Syllabus',
    'Review',
  ];

  @override
  void initState() {
    super.initState();
    _checkAuth();
    if (widget.testId != null) {
      _loadDraft();
    }
  }

  void _checkAuth() {
    if (!AuthService.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/login');
        }
      });
    }
  }

  Future<void> _loadDraft() async {
    if (widget.testId == null) return;

    setState(() {
      _isLoadingDraft = true;
      _draftError = null;
    });

    try {
      final test = await TestService.getTestById(widget.testId!);
      if (test == null) {
        setState(() {
          _draftError = 'Test not found';
          _isLoadingDraft = false;
        });
        return;
      }

      // Only allow editing drafts
      if (test.status != TestStatus.draft) {
        setState(() {
          _draftError = 'Only draft tests can be edited';
          _isLoadingDraft = false;
        });
        return;
      }

      // Check if user is the creator
      final currentUser = AuthService.currentUser;
      if (currentUser == null || test.createdBy != currentUser.id) {
        setState(() {
          _draftError = 'You can only edit your own tests';
          _isLoadingDraft = false;
        });
        return;
      }

      // Load questions from server
      List<Question> serverQuestions = [];
      try {
        serverQuestions = await QuestionService.getQuestionsSafe(
          testId: test.id,
        );
      } catch (e) {
        AppLogger.warning('Failed to load questions: $e');
      }

      // Load syllabus from server
      List<String> serverSyllabusNodeIds = [];
      try {
        final testSyllabus = await TestService.getTestSyllabus(test.id);
        serverSyllabusNodeIds = testSyllabus.map((ts) => ts.syllabusNodeId).toList();
      } catch (e) {
        AppLogger.warning('Failed to load syllabus: $e');
      }

      if (mounted) {
        setState(() {
          _loadedTest = test;
          _title = test.title;
          _description = test.description ?? '';
          _durationSec = test.durationSec;
          _marksPerQuestion = test.marksPerQuestion;
          _negativeMarks = test.negativeMarks;
          _testMode = test.testMode;
          _testKind = test.testKind;
          _groupId = test.groupId;
          _startsAt = test.startsAt;
          _endsAt = test.endsAt;
          _maxParticipants = test.maxParticipants;
          _allowLateJoin = test.allowLateJoin;
          _accessCode = test.accessCode;
          _joinCode = test.joinCode;

          _serverQuestions.addAll(serverQuestions);
          _serverSyllabusNodeIds.addAll(serverSyllabusNodeIds);

          _isLoadingDraft = false;
        });
      }
    } on AppError catch (e) {
      AppLogger.error('Load draft AppError: ${e.message}');
      if (mounted) {
        setState(() {
          _draftError = e.message;
          _isLoadingDraft = false;
        });
      }
    } catch (e) {
      AppLogger.error('Load draft unexpected error: $e');
      if (mounted) {
        setState(() {
          _draftError = 'Failed to load test';
          _isLoadingDraft = false;
        });
      }
    }
  }

  bool get _canProceedToNext {
    switch (_currentStep) {
      case 0:
        return _title.trim().isNotEmpty;
      case 1:
        return _canProceedFromConfiguration;
      case 2:
        return _questions.isNotEmpty || _serverQuestions.isNotEmpty;
      case 3:
        return true;
      case 4:
        return true;
      default:
        return false;
    }
  }

  bool get _canProceedFromConfiguration {
    // Validate group mode
    if (_testMode == 'group') {
      return _groupId != null && _groupId!.isNotEmpty;
    }
    return true;
  }

  void _nextStep() {
    if (_currentStep < 4 && _canProceedToNext) {
      setState(() => _currentStep++);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  // ─── SAVE DRAFT ───────────────────────────────────────────────

  Future<void> _saveDraft() async {
    if (_isSaving || _isPublishing) return;

    // Validate
    if (_title.trim().isEmpty) {
      _showError('Title is required');
      return;
    }

    if (_testMode == 'group' && (_groupId == null || _groupId!.isEmpty)) {
      _showError('Group selection is required for Group Test mode');
      return;
    }

    setState(() => _isSaving = true);

    try {
      AppLogger.info('Saving test draft: $_title');

      String testId;

      if (_isEditMode && _loadedTest != null) {
        // Update existing test
        await TestService.updateTest(
          testId: _loadedTest!.id,
          title: _title.trim(),
          description: _description.trim().isEmpty ? null : _description.trim(),
          durationSec: _durationSec,
          marksPerQuestion: _marksPerQuestion,
          negativeMarks: _negativeMarks,
          startsAt: _startsAt,
          endsAt: _endsAt,
          maxParticipants: _maxParticipants,
          allowLateJoin: _allowLateJoin,
          accessCode: _accessCode?.trim().isEmpty == true
              ? null
              : _accessCode?.trim(),
          joinCode: _joinCode?.trim().isEmpty == true
              ? null
              : _joinCode?.trim(),
          settings: _settingsForPersist(),
        );
        testId = _loadedTest!.id;
        AppLogger.info('Test updated: $testId');
      } else {
        // Create new test
        final test = await TestService.createTest(
          title: _title.trim(),
          description: _description.trim().isEmpty ? null : _description.trim(),
          durationSec: _durationSec,
          marksPerQuestion: _marksPerQuestion,
          negativeMarks: _negativeMarks,
          testMode: _testMode,
          groupId: _groupId,
          creationMethod: 'manual',
          startsAt: _startsAt,
          endsAt: _endsAt,
          maxParticipants: _maxParticipants,
          allowLateJoin: _allowLateJoin,
          accessCode: _accessCode?.trim().isEmpty == true
              ? null
              : _accessCode?.trim(),
          joinCode: _joinCode?.trim().isEmpty == true
              ? null
              : _joinCode?.trim(),
          settings: _settingsForPersist(),
        );
        testId = test.id;
        // The test now exists on the server: from here on this screen must
        // update it, never create another one — even if a later step fails.
        _loadedTest = test;
        AppLogger.info('Test created: $testId');
      }

      // Save new questions (from local drafts)
      await _persistLocalQuestions(testId, approve: false);

      // Save / remove syllabus selections
      await _persistSyllabusChanges(testId);

      // Reflect what is now on the server in local state
      await _syncPersistedContents(testId);

      if (mounted) {
        _showDraftSavedDialog(testId);
      }
    } on AppError catch (e) {
      AppLogger.error('Save draft AppError: ${e.message}');
      if (mounted) {
        _showError(e.message);
      }
    } catch (e) {
      AppLogger.error('Save draft unexpected error: $e');
      if (mounted) {
        _showError('Failed to save test. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showDraftSavedDialog(String testId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
        title: const Text('Draft Saved'),
        content: const Text('Your test has been saved as a draft.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.pop();
            },
            child: const Text('Back to Tests'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              // `_loadedTest` was already set when the test was persisted;
              // rebuild so the app bar / edit-mode UI reflects it.
              setState(() {});
            },
            child: const Text('Continue Editing'),
          ),
        ],
      ),
    );
  }

  // ─── PERSISTENCE HELPERS (shared by Save Draft and Publish) ───

  /// Creates every local draft question on the server. Each draft is removed
  /// from `_questions` as soon as its RPC succeeds, so if question N fails the
  /// already-created ones are not created again when the user retries.
  Future<void> _persistLocalQuestions(String testId,
      {required bool approve}) async {
    await TestCreationScreen.persistDraftQuestions(
      _questions,
      create: (draft) => QuestionService.createQuestion(
        testId: testId,
        questionText: draft.questionText,
        questionType: draft.questionType,
        options: draft.options
            .map((o) => {'id': o.id ?? '', 'text': o.text})
            .toList(),
        correctOption: draft.correctOptionIndex,
        explanation: draft.explanation,
        subjectId: draft.subjectId,
        topicNodeId: draft.topicNodeId,
        difficulty: draft.difficulty.name,
        marks: draft.marks,
        negativeMarks: draft.negativeMarks,
        language: draft.language,
      ),
      approve: approve ? QuestionService.approveQuestion : null,
    );
  }

  /// Adds newly selected syllabus nodes and removes deselected ones. Each
  /// node is moved into / out of `_serverSyllabusNodeIds` as soon as its RPC
  /// succeeds, so a retry never re-submits the same (test, node) pair.
  Future<void> _persistSyllabusChanges(String testId) async {
    await TestCreationScreen.persistSyllabusSelection(
      local: _syllabusNodeIds,
      server: _serverSyllabusNodeIds,
      add: (nodeId) =>
          TestService.addTestSyllabus(testId: testId, syllabusNodeId: nodeId),
      remove: (nodeId) => TestService.removeTestSyllabus(
          testId: testId, syllabusNodeId: nodeId),
    );
  }

  /// Reloads the server-side question list through the existing safe RPC
  /// (never `public.questions` directly; `correct_option` is not returned).
  /// Called only after the writes above succeeded. If the reload fails, the
  /// local drafts have already been removed from `_questions`, so nothing is
  /// recreated on retry — the list is simply refreshed on next open.
  Future<void> _syncPersistedContents(String testId) async {
    try {
      final serverQuestions =
          await QuestionService.getQuestionsSafe(testId: testId);
      if (mounted) {
        setState(() {
          _serverQuestions
            ..clear()
            ..addAll(serverQuestions);
        });
      }
    } catch (e) {
      AppLogger.warning(
          'Persisted questions saved but reload failed for $testId: $e');
    }
  }

  // ─── PUBLISH ──────────────────────────────────────────────────

  bool get _allServerQuestionsApproved =>
      _serverQuestions.every((q) => q.status == 'approved');

  List<String> _getPublishErrors() {
    final errors = <String>[];

    if (_title.trim().isEmpty) {
      errors.add('Enter a test title.');
    }

    if (_testMode == 'group' && (_groupId == null || _groupId!.isEmpty)) {
      errors.add('Select a group for Group Test.');
    }

    final allQuestions = [..._serverQuestions, ..._questions];
    if (allQuestions.isEmpty) {
      errors.add('Add at least one question.');
    } else {
      if (_serverQuestions.isNotEmpty && !_allServerQuestionsApproved) {
        final pending = _serverQuestions.where((q) => q.status != 'approved').length;
        errors.add('$pending question(s) need approval before publishing.');
      }

      for (var i = 0; i < _questions.length; i++) {
        if (!_questions[i].isValid) {
          errors.add('Question ${i + 1} is invalid.');
        }
      }
    }

    if (_durationSec == null || _durationSec! <= 0) {
      errors.add('Set a valid duration.');
    }

    return errors;
  }

  Future<void> _publishTest() async {
    if (_isSaving || _isPublishing) return;

    // Client-side validation
    final errors = _getPublishErrors();
    if (errors.isNotEmpty) {
      _showPublishErrors(errors);
      return;
    }

    setState(() => _isPublishing = true);

    try {
      AppLogger.info('Publishing test: $_title');

      String testId;

      if (_isEditMode && _loadedTest != null) {
        // Update existing test
        await TestService.updateTest(
          testId: _loadedTest!.id,
          title: _title.trim(),
          description: _description.trim().isEmpty ? null : _description.trim(),
          durationSec: _durationSec,
          marksPerQuestion: _marksPerQuestion,
          negativeMarks: _negativeMarks,
          startsAt: _startsAt,
          endsAt: _endsAt,
          maxParticipants: _maxParticipants,
          allowLateJoin: _allowLateJoin,
          accessCode: _accessCode?.trim().isEmpty == true
              ? null
              : _accessCode?.trim(),
          joinCode: _joinCode?.trim().isEmpty == true
              ? null
              : _joinCode?.trim(),
          settings: _settingsForPersist(),
        );
        testId = _loadedTest!.id;
        AppLogger.info('Test updated: $testId');
      } else {
        // Create new test
        final test = await TestService.createTest(
          title: _title.trim(),
          description: _description.trim().isEmpty ? null : _description.trim(),
          durationSec: _durationSec,
          marksPerQuestion: _marksPerQuestion,
          negativeMarks: _negativeMarks,
          testMode: _testMode,
          groupId: _groupId,
          creationMethod: 'manual',
          startsAt: _startsAt,
          endsAt: _endsAt,
          maxParticipants: _maxParticipants,
          allowLateJoin: _allowLateJoin,
          accessCode: _accessCode?.trim().isEmpty == true
              ? null
              : _accessCode?.trim(),
          joinCode: _joinCode?.trim().isEmpty == true
              ? null
              : _joinCode?.trim(),
          settings: _settingsForPersist(),
        );
        testId = test.id;
        // The test now exists on the server: a retry after a later failure
        // (e.g. publish rejected) must update it, not create another one.
        _loadedTest = test;
        AppLogger.info('Test created: $testId');
      }

      // Save new questions (from local drafts) and approve each
      await _persistLocalQuestions(testId, approve: true);

      // Save / remove syllabus selections
      await _persistSyllabusChanges(testId);

      // Reflect what is now on the server in local state, so that if
      // publishing fails below the user can retry without re-creating.
      await _syncPersistedContents(testId);

      // Publish test
      await TestService.publishTest(testId);
      AppLogger.info('Test published: $testId');

      if (mounted) {
        _showPublishSuccessDialog(testId);
      }
    } on AppError catch (e) {
      AppLogger.error('Publish test AppError: ${e.message}');
      if (mounted) {
        _showPublishErrorDialog(e.message);
      }
    } catch (e) {
      AppLogger.error('Publish test unexpected error: $e');
      if (mounted) {
        _showPublishErrorDialog(
            TestService.mapPublishError(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  void _showPublishSuccessDialog(String testId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
        title: const Text('Test Published'),
        content: const Text('Your test is now published and available.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/tests');
            },
            child: const Text('View in Browse'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/tests');
            },
            child: const Text('Back to Tests'),
          ),
        ],
      ),
    );
  }

  void _showPublishErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: AppColors.error, size: 48),
        title: const Text('Publish Failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _publishTest();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showPublishErrors(List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber, color: AppColors.warning, size: 48),
        title: const Text('Cannot Publish'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: errors
              .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error, size: 16, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e)),
                      ],
                    ),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  // ─── QUESTION MANAGEMENT ──────────────────────────────────────

  void _onQuestionsChanged(List<QuestionDraft> newDrafts) {
    setState(() {
      _questions.clear();
      _questions.addAll(newDrafts);
    });
  }

  void _onServerQuestionDeleted(String questionId) {
    setState(() {
      _serverQuestions.removeWhere((q) => q.id == questionId);
    });
  }

  void _onServerQuestionUpdated(Question updatedQuestion) {
    setState(() {
      final index = _serverQuestions.indexWhere((q) => q.id == updatedQuestion.id);
      if (index != -1) {
        _serverQuestions[index] = updatedQuestion;
      }
    });
  }

  void _onNewQuestionFromServer(Question newQuestion) {
    setState(() {
      _serverQuestions.add(newQuestion);
    });
  }

  // ─── TEST KIND (Self family) ──────────────────────────────────

  void _onTestKindChanged(TestKind kind) {
    setState(() {
      final changed = kind != _testKind;
      _testKind = kind;
      if (!changed) return;
      switch (kind) {
        case TestKind.practice:
          _startsAt = null;
          _endsAt = null;
          _durationSec = TestCreationScreen.practiceDefaultDurationSec;
          break;
        case TestKind.quick:
          _durationSec = TestCreationScreen.quickDefaultDurationSec;
          break;
        case TestKind.sectional:
        case TestKind.self:
          break;
      }
    });
  }

  /// `settings` to send with create/update: every key already stored on the
  /// server is preserved; `test_kind` is written only for the Self family.
  /// Returns null (= "leave settings untouched") for other modes when there
  /// is nothing stored, so Challenge with Friends / Group payloads are
  /// unchanged from before.
  Map<String, dynamic>? _settingsForPersist() {
    final existing = _loadedTest?.settings;
    if (_testMode == 'self') {
      final merged = _testKind.applyTo(existing);
      if (_testKind == TestKind.quick) {
        merged.putIfAbsent(TestCreationScreen.targetQuestionCountKey,
            () => TestCreationScreen.quickTargetQuestionCount);
      }
      return merged;
    }
    if (existing == null) return null;
    return {...existing}..remove(TestKind.settingsKey);
  }

  // ─── SYLLABUS MANAGEMENT ──────────────────────────────────────

  void _onSyllabusChanged(List<String> newNodeIds) {
    setState(() {
      _syllabusNodeIds.clear();
      _syllabusNodeIds.addAll(newNodeIds);
    });
  }

  // ─── BUILD ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isBusy = _isSaving || _isPublishing;

    if (_isLoadingDraft) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Loading Test...'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_draftError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Error'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 16),
                Text(
                  _draftError!,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Test' : 'Create Test'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: isBusy ? null : () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          const Divider(height: 1),
          Expanded(child: _buildCurrentStep()),
          _buildBottomBar(isBusy),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: List.generate(_stepTitles.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? AppColors.success
                        : isActive
                            ? AppColors.primaryLight
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.white : Colors.grey,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _stepTitles[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive
                        ? AppColors.primaryLight
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                  ),
                ),
                if (index < _stepTitles.length - 1) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.3),
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return StepBasicDetails(
          title: _title,
          description: _description,
          testMode: _testMode,
          testKind: _testKind,
          onTitleChanged: (value) => setState(() => _title = value),
          onDescriptionChanged: (value) => setState(() => _description = value),
          onTestModeChanged: (value) {
            setState(() {
              _testMode = value;
              if (value != 'group') {
                _groupId = null;
              }
            });
          },
          onTestKindChanged: _onTestKindChanged,
          titleError: null,
        );
      case 1:
        return StepConfiguration(
          durationSec: _durationSec,
          marksPerQuestion: _marksPerQuestion,
          negativeMarks: _negativeMarks,
          testMode: _testMode,
          groupId: _groupId,
          startsAt: _startsAt,
          endsAt: _endsAt,
          maxParticipants: _maxParticipants,
          allowLateJoin: _allowLateJoin,
          accessCode: _accessCode,
          joinCode: _joinCode,
          onChanged: (values) {
            setState(() {
              _durationSec = values['durationSec'] as int?;
              _marksPerQuestion = values['marksPerQuestion'] as double?;
              _negativeMarks = values['negativeMarks'] as double?;
              _testMode = values['testMode'] as String?;
              _groupId = values['groupId'] as String?;
              _startsAt = values['startsAt'] as DateTime?;
              _endsAt = values['endsAt'] as DateTime?;
              _maxParticipants = values['maxParticipants'] as int?;
              _allowLateJoin = values['allowLateJoin'] as bool? ?? false;
              _accessCode = values['accessCode'] as String?;
              _joinCode = values['joinCode'] as String?;
            });
          },
        );
      case 2:
        return StepQuestions(
          questions: _questions,
          serverQuestions: _serverQuestions,
          onQuestionsChanged: _onQuestionsChanged,
          onServerQuestionDeleted: _onServerQuestionDeleted,
          onServerQuestionUpdated: _onServerQuestionUpdated,
          onNewQuestionFromServer: _onNewQuestionFromServer,
          guidance: TestCreationScreen.questionsGuidance(_testMode, _testKind),
        );
      case 3:
        return StepSyllabus(
          selectedNodeIds: _syllabusNodeIds,
          serverSelectedNodeIds: _serverSyllabusNodeIds,
          onChanged: _onSyllabusChanged,
        );
      case 4:
        return StepReview(
          title: _title,
          description: _description,
          durationSec: _durationSec,
          marksPerQuestion: _marksPerQuestion,
          negativeMarks: _negativeMarks,
          testMode: _testMode,
          groupId: _groupId,
          startsAt: _startsAt,
          endsAt: _endsAt,
          maxParticipants: _maxParticipants,
          allowLateJoin: _allowLateJoin,
          accessCode: _accessCode,
          joinCode: _joinCode,
          questions: _questions,
          serverQuestions: _serverQuestions,
          syllabusNodeIds: _syllabusNodeIds,
          serverSyllabusNodeIds: _serverSyllabusNodeIds,
          onServerQuestionUpdated: _onServerQuestionUpdated,
          testKind: _testKind,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBottomBar(bool isBusy) {
    final isLastStep = _currentStep == 4;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep > 0)
              OutlinedButton(
                onPressed: isBusy ? null : _previousStep,
                child: const Text('Back'),
              )
            else
              const SizedBox.shrink(),
            const Spacer(),
            if (!isLastStep)
              FilledButton(
                onPressed: isBusy || !_canProceedToNext ? null : _nextStep,
                child: const Text('Next'),
              )
            else ...[
              OutlinedButton(
                onPressed: isBusy ? null : _saveDraft,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Draft'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: isBusy ? null : _publishTest,
                child: _isPublishing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Publish'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
