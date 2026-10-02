/// Category keys mirror the live `app_tutorials.category` CHECK constraint
/// (0100_app_tutorials.sql) exactly — never invented client-side.
enum TutorialCategory {
  gettingStarted('getting_started', '🚀 Shuruat', 'Getting Started'),
  testsChallenges('tests_challenges', '📝 Tests & Challenges', 'Tests & Challenges'),
  studyNotes('study_notes', '📖 My Study & Notes', 'My Study & Notes'),
  questionBankPyq('question_bank_pyq', '📚 Question Bank & PYQ', 'Question Bank & PYQ'),
  omr('omr', '⭕ Digital OMR Sheet', 'Digital OMR Sheet'),
  mistakeVaultRadio('mistake_vault_radio', '⚡ Mistake Vault & Radio', 'Mistake Vault & Radio');

  const TutorialCategory(this.dbValue, this.chipLabel, this.title);
  final String dbValue;
  final String chipLabel;
  final String title;

  static TutorialCategory? fromDb(String? value) {
    for (final c in TutorialCategory.values) {
      if (c.dbValue == value) return c;
    }
    return null;
  }
}

/// One how-to-use-the-app video, as stored in `app_tutorials`.
final class AppTutorial {
  const AppTutorial({
    required this.id,
    required this.category,
    required this.title,
    this.titleHi,
    this.description,
    required this.youtubeVideoId,
    this.durationText,
    required this.displayOrder,
  });

  final String id;
  final TutorialCategory? category;
  final String title;
  final String? titleHi;
  final String? description;
  final String youtubeVideoId;
  final String? durationText;
  final int displayOrder;

  factory AppTutorial.fromJson(Map<String, dynamic> json) {
    return AppTutorial(
      id: json['id'] as String,
      category: TutorialCategory.fromDb(json['category'] as String?),
      title: json['title'] as String? ?? '',
      titleHi: json['title_hi'] as String?,
      description: json['description'] as String?,
      youtubeVideoId: json['youtube_video_id'] as String? ?? '',
      durationText: json['duration_text'] as String?,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 1,
    );
  }
}
