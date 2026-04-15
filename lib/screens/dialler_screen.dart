import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/call_state.dart';
import '../models/model_state.dart';
import '../services/native_bridge.dart';
import '../widgets/dial_pad.dart';

class DiallerScreen extends StatefulWidget {
  const DiallerScreen({super.key});

  @override
  State<DiallerScreen> createState() => _DiallerScreenState();
}

class _DiallerScreenState extends State<DiallerScreen> {
  String _number = '';

  void _onKey(String digit) => setState(() => _number += digit);

  void _onDelete() {
    if (_number.isNotEmpty) {
      setState(() => _number = _number.substring(0, _number.length - 1));
    }
  }

  Future<void> _onCall() async {
    if (_number.isEmpty) return;
    final callState = context.read<CallState>();
    callState.startDialing(_number);
    try {
      await NativeBridge.instance.dialNumber(_number);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to place call: $e')),
        );
        callState.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check model status once on first build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final modelState = context.read<ModelState>();
      if (modelState.status == ModelStatus.unknown) {
        final result = await NativeBridge.instance.checkModel();
        if (context.mounted) modelState.applyCheckResult(result);
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('KAVACH'),
        centerTitle: true,
        actions: [
          _ModelStatusChip(
            onTap: () => Navigator.of(context).pushNamed('/model'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: DialPad(
            displayNumber: _number,
            onKeyTap: _onKey,
            onDelete: _onDelete,
            onCall: _onCall,
            callEnabled: _number.isNotEmpty,
          ),
        ),
      ),
    );
  }
}

class _ModelStatusChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ModelStatusChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<ModelState>().status;

    final (icon, label, color) = switch (status) {
      ModelStatus.ready       => (Icons.security, 'AI On', Colors.green),
      ModelStatus.downloading => (Icons.downloading, 'Downloading', Colors.blue),
      ModelStatus.loading     => (Icons.hourglass_top, 'Loading', Colors.orange),
      ModelStatus.downloaded  => (Icons.download_done, 'Load AI', Colors.blue),
      _                       => (Icons.security_outlined, 'Setup AI', Colors.grey),
    };

    return GestureDetector(
      onTap: onTap,
      child: Chip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(fontSize: 12, color: color)),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        backgroundColor: color.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
