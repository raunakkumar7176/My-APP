/// One `public.academic_special_days` row (migration 0068) — a National/
/// International observance day, jayanti, or festival, matched by day+month.
final class AcademicSpecialDay {
  const AcademicSpecialDay({
    required this.id,
    required this.day,
    required this.month,
    this.year,
    required this.title,
    required this.category,
    required this.significance,
    this.examNotes,
    this.iconKey = 'star',
  });

  final String id;
  final int day;
  final int month;
  final int? year;
  final String title;

  /// 'national_day' | 'international_day' | 'jayanti' | 'festival'.
  final String category;
  final String significance;
  final String? examNotes;
  final String iconKey;

  String get categoryLabel {
    switch (category) {
      case 'national_day':
        return 'National Day';
      case 'international_day':
        return 'International Day';
      case 'jayanti':
        return 'Jayanti';
      case 'festival':
        return 'Festival';
      default:
        return 'Special Day';
    }
  }

  factory AcademicSpecialDay.fromJson(Map<String, dynamic> json) {
    return AcademicSpecialDay(
      id: json['id'] as String,
      day: (json['day'] as num).toInt(),
      month: (json['month'] as num).toInt(),
      year: (json['year'] as num?)?.toInt(),
      title: json['title'] as String,
      category: json['category'] as String,
      significance: json['significance'] as String,
      examNotes: json['exam_notes'] as String?,
      iconKey: json['icon_key'] as String? ?? 'star',
    );
  }
}
