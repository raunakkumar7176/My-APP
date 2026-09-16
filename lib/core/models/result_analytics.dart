final class SubjectBreakdownItem {
  const SubjectBreakdownItem({
    required this.subjectId,
    required this.subjectName,
    required this.attempted,
    required this.correct,
    required this.wrong,
    required this.unanswered,
  });

  final String subjectId;
  final String subjectName;
  final int attempted;
  final int correct;
  final int wrong;
  final int unanswered;

  int get total => attempted + unanswered;
  double get accuracy => attempted > 0 ? (correct / attempted) * 100 : 0;

  factory SubjectBreakdownItem.fromRaw({
    required String subjectId,
    required String subjectName,
    required Map<String, dynamic> data,
  }) {
    return SubjectBreakdownItem(
      subjectId: subjectId,
      subjectName: subjectName,
      attempted: (data['attempted'] as num?)?.toInt() ?? 0,
      correct: (data['correct'] as num?)?.toInt() ?? 0,
      wrong: (data['wrong'] as num?)?.toInt() ?? 0,
      unanswered: (data['unanswered'] as num?)?.toInt() ?? 0,
    );
  }
}

final class TopicBreakdownItem {
  const TopicBreakdownItem({
    required this.topicId,
    required this.topicName,
    required this.attempted,
    required this.correct,
    required this.wrong,
    required this.unanswered,
  });

  final String topicId;
  final String topicName;
  final int attempted;
  final int correct;
  final int wrong;
  final int unanswered;

  int get total => attempted + unanswered;
  double get accuracy => attempted > 0 ? (correct / attempted) * 100 : 0;

  factory TopicBreakdownItem.fromRaw({
    required String topicId,
    required String topicName,
    required Map<String, dynamic> data,
  }) {
    return TopicBreakdownItem(
      topicId: topicId,
      topicName: topicName,
      attempted: (data['attempted'] as num?)?.toInt() ?? 0,
      correct: (data['correct'] as num?)?.toInt() ?? 0,
      wrong: (data['wrong'] as num?)?.toInt() ?? 0,
      unanswered: (data['unanswered'] as num?)?.toInt() ?? 0,
    );
  }
}

