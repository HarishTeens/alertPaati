import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/call_state.dart';
import '../models/fraud_result.dart';
import '../widgets/fraud_alert_banner.dart';

class DebriefScreen extends StatelessWidget {
  const DebriefScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final callState = context.read<CallState>();
    final latest = callState.latestFraudResult ?? FraudResult.safe();
    final history = callState.fraudHistory;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Debrief'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            callState.reset();
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CallSummaryCard(callState: callState),
          const SizedBox(height: 16),
          _FraudVerdictCard(result: latest),
          if (latest.redFlags.isNotEmpty) ...[
            const SizedBox(height: 16),
            _RedFlagsCard(flags: latest.redFlags),
          ],
          if (callState.transcript.isNotEmpty) ...[
            const SizedBox(height: 16),
            _TranscriptCard(transcript: callState.transcript),
          ],
          if (history.length > 1) ...[
            const SizedBox(height: 16),
            _FraudTimelineCard(history: history),
          ],
          const SizedBox(height: 24),
          _ActionButtons(
            onBlock: () => _blockNumber(context, callState.phoneNumber),
            onReport: () => _reportNumber(context, callState.phoneNumber),
            onDismiss: () {
              callState.reset();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
    );
  }

  void _blockNumber(BuildContext context, String number) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$number added to block list')),
    );
  }

  void _reportNumber(BuildContext context, String number) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$number reported to fraud database')),
    );
  }
}

class _CallSummaryCard extends StatelessWidget {
  final CallState callState;
  const _CallSummaryCard({required this.callState});

  @override
  Widget build(BuildContext context) {
    final dur = callState.duration;
    final durStr =
        '${dur.inMinutes.toString().padLeft(2, '0')}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}';

    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.call)),
        title: Text(callState.phoneNumber,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Duration: $durStr'),
        trailing: Icon(
          callState.currentFraudLevel == FraudLevel.safe
              ? Icons.verified_user
              : Icons.gpp_bad,
          color: callState.currentFraudLevel == FraudLevel.safe
              ? Colors.green
              : Colors.red,
          size: 32,
        ),
      ),
    );
  }
}

class _FraudVerdictCard extends StatelessWidget {
  final FraudResult result;
  const _FraudVerdictCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final (color, icon, title) = switch (result.level) {
      FraudLevel.danger => (Colors.red, Icons.warning_amber_rounded, 'Fraud Detected'),
      FraudLevel.suspicious => (Colors.orange, Icons.info_outline, 'Suspicious Call'),
      _ => (Colors.green, Icons.check_circle_outline, 'Call Appears Safe'),
    };

    return Card(
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 10),
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                FraudScoreRing(score: result.score, size: 56),
              ],
            ),
            if (result.explanation.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'AI Analysis',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 4),
              Text(result.explanation,
                  style: const TextStyle(fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RedFlagsCard extends StatelessWidget {
  final List<String> flags;
  const _RedFlagsCard({required this.flags});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Red Flags',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...flags.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.flag, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  final String transcript;
  const _TranscriptCard({required this.transcript});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: const Text('Call Transcript',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: const Icon(Icons.text_snippet_outlined),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(transcript,
                style: const TextStyle(fontSize: 13, height: 1.6)),
          ),
        ],
      ),
    );
  }
}

class _FraudTimelineCard extends StatelessWidget {
  final List<FraudResult> history;
  const _FraudTimelineCard({required this.history});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fraud Risk Over Time',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: history
                    .map((r) => Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 2),
                            child: Container(
                              height: 60 * r.score + 4,
                              decoration: BoxDecoration(
                                color: _colorFor(r.level),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorFor(FraudLevel level) => switch (level) {
        FraudLevel.danger => Colors.red,
        FraudLevel.suspicious => Colors.orange,
        _ => Colors.green,
      };
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onBlock;
  final VoidCallback onReport;
  final VoidCallback onDismiss;

  const _ActionButtons({
    required this.onBlock,
    required this.onReport,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FilledButton.icon(
          onPressed: onBlock,
          icon: const Icon(Icons.block),
          label: const Text('Block Number'),
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: Colors.red),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onReport,
          icon: const Icon(Icons.report_outlined),
          label: const Text('Report to Database'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onDismiss,
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}
