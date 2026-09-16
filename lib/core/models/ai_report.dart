final class AiReport {
  const AiReport({
    required this.id,
    required this.resultId,
    required this.userId,
    required this.testId,
    this.summary,
    this.strengths,
    this.weaknesses,
    this.recommendations,
    this.detailedAnalysis,
    this.modelUsed,
    this.tokensUsed,
    required this.generatedAt,
  });

  final String id;
  final String resultId;
  final String userId;
  final String testId;
  final String? summary;
  final List<String>? strengths;
  final List<String>? weaknesses;
  final List<String>? recommendations;
  final String? detailedAnalysis;
  final String? modelUsed;
  final int? tokensUsed;
  final DateTime generatedAt;

  factory AiReport.fromJson(Map<String, dynamic> json) {
    return AiReport(
      id: json['id'] as String,
      resultId: json['result_id'] as String,
      userId: json['user_id'] as String,
      testId: json['test_id'] as String,
      summary: json['summary'] as String?,
      strengths: (json['strengths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      weaknesses: (json['weaknesses'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      recommendations: (json['recommendations'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      detailedAnalysis: json['detailed_analysis'] as String?,
      modelUsed: json['model_used'] as String?,
      tokensUsed: (json['tokens_used'] as num?)?.toInt(),
      generatedAt: DateTime.parse(json['generated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'result_id': resultId,
      'user_id': userId,
      'test_id': testId,
      'summary': summary,
      'strengths': strengths,
      'weaknesses': weaknesses,
      'recommendations': recommendations,
      'detailed_analysis': detailedAnalysis,
      'model_used': modelUsed,
      'tokens_used': tokensUsed,
      'generated_at': generatedAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiReport &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          resultId == other.resultId &&
          userId == other.userId;

  @override
  int get hashCode => Object.hash(id, resultId, userId);
}
