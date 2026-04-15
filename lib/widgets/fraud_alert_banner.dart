import 'package:flutter/material.dart';
import '../models/call_state.dart';
import '../models/fraud_result.dart';

class FraudAlertBanner extends StatelessWidget {
  final FraudResult result;

  const FraudAlertBanner({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    if (!result.isThreat) return const SizedBox.shrink();

    final (bg, icon, title) = switch (result.level) {
      FraudLevel.danger => (
          Colors.red.shade900,
          Icons.warning_amber_rounded,
          'FRAUD DETECTED'
        ),
      FraudLevel.suspicious => (
          Colors.orange.shade800,
          Icons.info_outline_rounded,
          'SUSPICIOUS ACTIVITY'
        ),
      _ => (Colors.green.shade800, Icons.check_circle_outline, 'SAFE'),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '${(result.score * 100).toStringAsFixed(0)}% risk',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          if (result.explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              result.explanation,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (result.redFlags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: result.redFlags
                  .take(3)
                  .map((f) => Chip(
                        label: Text(f,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white)),
                        backgroundColor: Colors.white24,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class FraudScoreRing extends StatelessWidget {
  final double score; // 0.0–1.0
  final double size;

  const FraudScoreRing({super.key, required this.score, this.size = 64});

  Color get _color {
    if (score < 0.3) return Colors.green;
    if (score < 0.6) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score,
            strokeWidth: 5,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation(_color),
          ),
          Text(
            (score * 100).toStringAsFixed(0),
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.bold,
              fontSize: size * 0.22,
            ),
          ),
        ],
      ),
    );
  }
}
