import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/call_state.dart';
import '../services/native_bridge.dart';
import '../widgets/call_controls.dart';
import '../widgets/fraud_alert_banner.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  Timer? _durationTimer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  String get _formattedDuration {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _endCall() async {
    _durationTimer?.cancel();
    await NativeBridge.instance.endCall();
  }

  Future<void> _toggleMute() async {
    final cs = context.read<CallState>();
    cs.toggleMute();
    await NativeBridge.instance.setMute(cs.isMuted);
  }

  Future<void> _toggleSpeaker() async {
    final cs = context.read<CallState>();
    cs.toggleSpeaker();
    await NativeBridge.instance.setSpeaker(cs.isSpeakerOn);
  }

  @override
  Widget build(BuildContext context) {
    final callState = context.watch<CallState>();
    final fraudResult = callState.latestFraudResult;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Fraud Alert Banner ──────────────────────────────────────
            if (fraudResult != null && fraudResult.isThreat)
              FraudAlertBanner(result: fraudResult),

            // ── Caller Info ─────────────────────────────────────────────
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallerAvatar(
                    name: callState.callerName.isNotEmpty
                        ? callState.callerName
                        : callState.phoneNumber,
                    fraudLevel: callState.currentFraudLevel,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    callState.callerName.isNotEmpty
                        ? callState.callerName
                        : callState.phoneNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatusRow(
                    status: callState.status,
                    duration: _formattedDuration,
                    isRecording: callState.isRecording,
                  ),
                  const SizedBox(height: 32),

                  // Fraud score ring (shown during active call)
                  if (fraudResult != null)
                    Column(
                      children: [
                        FraudScoreRing(score: fraudResult.score, size: 80),
                        const SizedBox(height: 8),
                        Text(
                          'Fraud Risk',
                          style: TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),

                  // Live transcript preview
                  if (callState.transcript.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _TranscriptPreview(text: callState.transcript),
                  ],
                ],
              ),
            ),

            // ── Call Controls ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: CallControls(
                isMuted: callState.isMuted,
                isSpeakerOn: callState.isSpeakerOn,
                onToggleMute: _toggleMute,
                onToggleSpeaker: _toggleSpeaker,
                onEndCall: _endCall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallerAvatar extends StatelessWidget {
  final String name;
  final FraudLevel fraudLevel;

  const _CallerAvatar({required this.name, required this.fraudLevel});

  Color get _ringColor => switch (fraudLevel) {
        FraudLevel.danger => Colors.red,
        FraudLevel.suspicious => Colors.orange,
        FraudLevel.safe => Colors.green,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _ringColor, width: 3),
      ),
      child: CircleAvatar(
        backgroundColor: Colors.white12,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 40, color: Colors.white),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final CallStatus status;
  final String duration;
  final bool isRecording;

  const _StatusRow({
    required this.status,
    required this.duration,
    required this.isRecording,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      CallStatus.dialing => 'Calling…',
      CallStatus.ringing => 'Ringing…',
      CallStatus.active => duration,
      CallStatus.ended => 'Call ended',
      _ => '',
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 16)),
        if (isRecording) ...[
          const SizedBox(width: 10),
          const _RecordingDot(),
          const SizedBox(width: 4),
          const Text('REC',
              style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  letterSpacing: 1.2)),
        ],
      ],
    );
  }
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Colors.redAccent),
      ),
    );
  }
}

class _TranscriptPreview extends StatelessWidget {
  final String text;
  const _TranscriptPreview({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
