import 'dart:convert';
import 'dart:math';

import '../../../core/models/question.dart';

/// Deterministic FNV-1a hash, truncated to 32-bit for use as a seed.
/// Identical across runs, platforms and Dart versions (32-bit ops avoid
/// JavaScript integer overflow).
int fnv1aHash(String input) {
  const int fnvOffsetBasis = 0x811c9dc5;
  const int fnvPrime = 0x01000193;
  var hash = fnvOffsetBasis;
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash;
}

/// Presentation-only shuffling seeded by the attempt id, so a resumed
/// attempt always sees the same order. Scoring is unaffected (the server
/// scores by question/option id).
abstract final class DeterministicShuffle {
  static List<Question> questions(List<Question> questions, String seed) =>
      List<Question>.from(questions)..shuffle(Random(fnv1aHash(seed)));

  static List<QuestionOption> options(
    List<QuestionOption> options,
    String seed,
  ) => List<QuestionOption>.from(options)..shuffle(Random(fnv1aHash(seed)));
}
