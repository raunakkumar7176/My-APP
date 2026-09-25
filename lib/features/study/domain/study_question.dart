/// Model representing a practice question in the Study module.
final class StudyQuestion {
  const StudyQuestion({
    required this.id,
    required this.chapterId,
    this.topicId,
    required this.question,
    required this.options,
    required this.correctOption,
    required this.explanation,
    this.difficulty = 'medium',
  });

  final String id;
  final String chapterId;
  final String? topicId;
  final String question;
  final List<String> options;
  final int correctOption;
  final String explanation;
  final String difficulty;

  factory StudyQuestion.fromMap(
    Map<String, dynamic> map, {
    required String languageCode,
  }) {
    final isHindi = languageCode == 'hi';

    // Question text with fallback between 'question' and 'question_text'
    String qText = '';
    if (map['question'] is String && (map['question'] as String).isNotEmpty) {
      qText = map['question'] as String;
    } else if (isHindi &&
        map['question_text_hi'] is String &&
        (map['question_text_hi'] as String).isNotEmpty) {
      qText = map['question_text_hi'] as String;
    } else if (map['question_text'] is String) {
      qText = map['question_text'] as String;
    }

    // Options with robust extraction (handles [{'id': 'opt_1', 'text': '...'}] or ['...'])
    final List<String> opts = [];
    final rawOpts = (isHindi && map['options_hi'] != null)
        ? map['options_hi']
        : map['options'];
    if (rawOpts is List) {
      for (final item in rawOpts) {
        if (item is Map) {
          opts.add((item['text'] as String?) ?? item.toString());
        } else {
          opts.add(item.toString());
        }
      }
    }

    // Explanation with fallback
    String expl = '';
    if (isHindi &&
        map['explanation_hi'] is String &&
        (map['explanation_hi'] as String).isNotEmpty) {
      expl = map['explanation_hi'] as String;
    } else if (map['explanation'] is String) {
      expl = map['explanation'] as String;
    }

    return StudyQuestion(
      id: map['id'] as String,
      chapterId: (map['chapter_id'] as String?) ?? '',
      topicId: map['topic_id'] as String?,
      question: qText,
      options: opts,
      correctOption: (map['correct_option'] as num?)?.toInt() ?? 0,
      explanation: expl,
      difficulty: (map['difficulty'] as String?) ?? 'medium',
    );
  }
}
