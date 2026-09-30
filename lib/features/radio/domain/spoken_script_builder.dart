import 'radio_track.dart';

/// Splits a [RadioTrack] into the two phrases Radio Mode speaks separately
/// (question, then — after the hands-free pause, if any — the answer) so
/// the player can insert a real pause between TTS calls rather than baking
/// a fixed delay into one long utterance.
///
/// Built only from fields that actually exist on the real `Question` model
/// (`question`, `options`, `explanation`, `language`) — there is no Hindi
/// variant column on a per-test question (unlike `question_bank`), so
/// nothing here invents `questionTextHi`/`explanationHi` text that was
/// never in the database.
abstract final class SpokenScriptBuilder {
  static String questionPhrase(RadioTrack track) {
    return 'Sawal: ${track.question.question}';
  }

  static String? answerPhrase(RadioTrack track) {
    final correctIndex = track.correctOption;
    final options = track.question.options;
    if (correctIndex == null || options == null || correctIndex >= options.length) {
      return null; // No real answer key available — never guessed.
    }
    final buffer = StringBuffer(
      'Sahi uttar hai vikalp ${correctIndex + 1}: ${options[correctIndex].text}.',
    );
    final explanation = track.question.explanation;
    if (explanation != null && explanation.trim().isNotEmpty) {
      buffer.write(' Karan: $explanation');
    }
    return buffer.toString();
  }

  /// TTS locale: this app's questions are written in whichever language
  /// `question.language` actually records ('en'/'hi'/'hinglish') — the
  /// voice follows that real field rather than always defaulting to
  /// Hindi regardless of the question's actual language.
  static String localeFor(RadioTrack track) {
    switch (track.question.language) {
      case 'hi':
        return 'hi-IN';
      default:
        return 'en-IN';
    }
  }
}
