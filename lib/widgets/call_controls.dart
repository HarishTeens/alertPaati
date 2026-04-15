import 'package:flutter/material.dart';

class CallControls extends StatelessWidget {
  final bool isMuted;
  final bool isSpeakerOn;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onEndCall;

  const CallControls({
    super.key,
    required this.isMuted,
    required this.isSpeakerOn,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: isMuted ? Icons.mic_off : Icons.mic,
          label: isMuted ? 'Unmute' : 'Mute',
          active: isMuted,
          onTap: onToggleMute,
        ),
        _EndCallButton(onTap: onEndCall),
        _ControlButton(
          icon: isSpeakerOn ? Icons.volume_up : Icons.volume_down,
          label: isSpeakerOn ? 'Speaker' : 'Earpiece',
          active: isSpeakerOn,
          onTap: onToggleSpeaker,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final bg = active
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;
  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
            ),
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 6),
          const Text('End', style: TextStyle(fontSize: 12, color: Colors.red)),
        ],
      ),
    );
  }
}
