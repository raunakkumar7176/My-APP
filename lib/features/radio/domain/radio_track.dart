import '../../../core/models/question.dart';

/// One question in a Radio Mode playlist, paired with the real correct
/// option index it was loaded with (from `ResultsController.correctOptionFor`
/// — the same post-submission answer key the Review screen already uses;
/// never guessed, and null skips speaking an answer at all rather than
/// inventing one).
final class RadioTrack {
  const RadioTrack({required this.question, required this.correctOption});

  final Question question;
  final int? correctOption;
}
