import 'call_state.dart';

class FraudResult {
  final double score; // 0.0 (safe) to 1.0 (certain fraud)
  final FraudLevel level;
  final String explanation;
  final List<String> redFlags;
  final DateTime timestamp;

  const FraudResult({
    required this.score,
    required this.level,
    required this.explanation,
    required this.redFlags,
    required this.timestamp,
  });

  factory FraudResult.safe() => FraudResult(
        score: 0.0,
        level: FraudLevel.safe,
        explanation: 'No fraud indicators detected.',
        redFlags: [],
        timestamp: DateTime.now(),
      );

  factory FraudResult.fromMap(Map<String, dynamic> map) {
    final levelStr = map['level'] as String? ?? 'safe';
    final level = switch (levelStr) {
      'danger' => FraudLevel.danger,
      'suspicious' => FraudLevel.suspicious,
      _ => FraudLevel.safe,
    };
    return FraudResult(
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
      level: level,
      explanation: map['explanation'] as String? ?? '',
      redFlags: List<String>.from(map['redFlags'] as List? ?? []),
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'score': score,
        'level': level.name,
        'explanation': explanation,
        'redFlags': redFlags,
        'timestamp': timestamp.toIso8601String(),
      };

  bool get isThreat => level != FraudLevel.safe;
}
