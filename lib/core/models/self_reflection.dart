enum ConfidenceLevel { veryLow, low, medium, high, veryHigh }

enum ExpectedPerformance { below40, range4059, range6074, range7589, range90 }

class SelfReflection {
  const SelfReflection({
    required this.confidence,
    required this.expectedPerformance,
    this.optionalReflection,
  });

  final ConfidenceLevel confidence;
  final ExpectedPerformance expectedPerformance;
  final String? optionalReflection;

  String get confidenceLabel {
    switch (confidence) {
      case ConfidenceLevel.veryLow:
        return 'Very Low';
      case ConfidenceLevel.low:
        return 'Low';
      case ConfidenceLevel.medium:
        return 'Medium';
      case ConfidenceLevel.high:
        return 'High';
      case ConfidenceLevel.veryHigh:
        return 'Very High';
    }
  }

  String get expectedRangeLabel {
    switch (expectedPerformance) {
      case ExpectedPerformance.below40:
        return 'Below 40%';
      case ExpectedPerformance.range4059:
        return '40–59%';
      case ExpectedPerformance.range6074:
        return '60–74%';
      case ExpectedPerformance.range7589:
        return '75–89%';
      case ExpectedPerformance.range90:
        return '90%+';
    }
  }

  double get expectedMidpoint {
    switch (expectedPerformance) {
      case ExpectedPerformance.below40:
        return 20;
      case ExpectedPerformance.range4059:
        return 50;
      case ExpectedPerformance.range6074:
        return 67;
      case ExpectedPerformance.range7589:
        return 82;
      case ExpectedPerformance.range90:
        return 95;
    }
  }
}
