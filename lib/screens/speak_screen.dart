import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/native_bridge.dart';

class SpeakScreen extends StatefulWidget {
  const SpeakScreen({super.key});

  @override
  State<SpeakScreen> createState() => _SpeakScreenState();
}

enum _ListenState { idle, listening, processing }

class _SpeakScreenState extends State<SpeakScreen>
    with SingleTickerProviderStateMixin {
  _ListenState _state = _ListenState.idle;
  final List<String> _finalTexts = [];
  String _partialText = '';
  StreamSubscription<Map<String, dynamic>>? _sub;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _sub = NativeBridge.instance.speechStream.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final status = event['status'] as String? ?? '';
    switch (status) {
      case 'listening':
        setState(() => _state = _ListenState.listening);
        _pulseController.repeat(reverse: true);
      case 'processing':
        setState(() => _state = _ListenState.processing);
        _pulseController.stop();
        _pulseController.reset();
      case 'result':
        final text = event['text'] as String? ?? '';
        final isFinal = event['isFinal'] as bool? ?? false;
        setState(() {
          if (isFinal) {
            if (text.isNotEmpty) _finalTexts.add(text);
            _partialText = '';
          } else {
            _partialText = text;
          }
        });
        _scrollToBottom();
      case 'idle':
        setState(() {
          _state = _ListenState.idle;
          _partialText = '';
        });
        _pulseController.stop();
        _pulseController.reset();
      case 'error':
        final code = event['code'];
        final msg = event['message'] as String?;
        setState(() {
          _state = _ListenState.idle;
          _partialText = '';
        });
        _pulseController.stop();
        _pulseController.reset();
        if (msg != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        } else if (code != null) {
          // Error code 7 = no match, 6 = timeout — these are auto-restarted natively
          // Only show snackbar for unexpected errors
          if (code != 7 && code != 6) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Speech error (code $code)')),
            );
          }
        }
    }
  }

  Future<void> _toggleListening() async {
    if (_state != _ListenState.idle) {
      await NativeBridge.instance.stopListening();
      return;
    }
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (status.isGranted) {
      await NativeBridge.instance.startListening();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required')),
      );
    }
  }

  void _clear() {
    setState(() {
      _finalTexts.clear();
      _partialText = '';
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = _state != _ListenState.idle;

    return Column(
      children: [
        // ── Transcript area ───────────────────────────────────────────
        Expanded(
          child: (_finalTexts.isEmpty && _partialText.isEmpty)
              ? Center(
                  child: Text(
                    'Tap the mic and start speaking',
                    style: TextStyle(color: scheme.outline),
                  ),
                )
              : ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  children: [
                    for (final t in _finalTexts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(t, style: const TextStyle(fontSize: 16, height: 1.5)),
                      ),
                    if (_partialText.isNotEmpty)
                      Text(
                        _partialText,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
        ),

        // ── Controls ──────────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(
              24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
          child: Column(
            children: [
              // Status label
              Text(
                switch (_state) {
                  _ListenState.idle       => 'Tap to start',
                  _ListenState.listening  => 'Listening…',
                  _ListenState.processing => 'Processing…',
                },
                style: TextStyle(
                  fontSize: 13,
                  color: isActive ? scheme.primary : scheme.outline,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 16),

              // Mic button with pulse animation
              ScaleTransition(
                scale: isActive ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
                child: GestureDetector(
                  onTap: _toggleListening,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? scheme.error : scheme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: (isActive ? scheme.error : scheme.primary)
                              .withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      isActive ? Icons.stop : Icons.mic,
                      color: isActive ? scheme.onError : scheme.onPrimary,
                      size: 32,
                    ),
                  ),
                ),
              ),

              // Clear button
              if (_finalTexts.isNotEmpty || _partialText.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(foregroundColor: scheme.outline),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
