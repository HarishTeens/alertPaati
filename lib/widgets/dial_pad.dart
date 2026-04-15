import 'package:flutter/material.dart';

class DialPad extends StatelessWidget {
  final String displayNumber;
  final ValueChanged<String> onKeyTap;
  final VoidCallback onDelete;
  final VoidCallback onCall;
  final bool callEnabled;

  const DialPad({
    super.key,
    required this.displayNumber,
    required this.onKeyTap,
    required this.onDelete,
    required this.onCall,
    this.callEnabled = true,
  });

  static const _keys = [
    ('1', ''), ('2', 'ABC'), ('3', 'DEF'),
    ('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO'),
    ('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ'),
    ('*', ''), ('0', '+'), ('#', ''),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _NumberDisplay(number: displayNumber, onDelete: onDelete),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: _keys
              .map((k) => _DialKey(
                    digit: k.$1,
                    letters: k.$2,
                    onTap: () => onKeyTap(k.$1),
                  ))
              .toList(),
        ),
        const SizedBox(height: 24),
        _CallButton(onCall: onCall, enabled: callEnabled),
      ],
    );
  }
}

class _NumberDisplay extends StatelessWidget {
  final String number;
  final VoidCallback onDelete;

  const _NumberDisplay({required this.number, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            number.isEmpty ? 'Enter number' : number,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w300,
              letterSpacing: 4,
              color: number.isEmpty
                  ? Theme.of(context).colorScheme.outline
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        if (number.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.backspace_outlined),
            onPressed: onDelete,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }
}

class _DialKey extends StatelessWidget {
  final String digit;
  final String letters;
  final VoidCallback onTap;

  const _DialKey(
      {required this.digit, required this.letters, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final VoidCallback onCall;
  final bool enabled;

  const _CallButton({required this.onCall, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onCall : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.green : Colors.grey.shade400,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: const Icon(Icons.call, color: Colors.white, size: 32),
      ),
    );
  }
}
