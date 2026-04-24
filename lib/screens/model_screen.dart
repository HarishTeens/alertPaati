import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/model_state.dart';
import '../services/native_bridge.dart';

// LiteRT .litertlm model files — compatible with MediaPipe LlmInference.setModelPath().
// Accept terms at huggingface.co/litert-community/gemma-4-E2B-it-litert-lm first.
const _kModelVariants = [
  _ModelVariant(
    label: 'Gemma 4 — E2B compressed (recommended)',
    fileName: 'gemma-4-E2B-it.litertlm',
    sizeLabel: '~2.6 GB',
    url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm'
        '/resolve/main/gemma-4-E2B-it.litertlm',
    useGpu: true,
  ),
];

class ModelScreen extends StatefulWidget {
  const ModelScreen({super.key});

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  final _ModelVariant _selected = _kModelVariants.first;
  StreamSubscription<Map<String, dynamic>>? _progressSub;

  @override
  void initState() {
    super.initState();
    final modelState = context.read<ModelState>();
    _progressSub = NativeBridge.instance.bindDownloadProgress(modelState);
    _refreshStatus();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final result = await NativeBridge.instance.checkModel();
    if (mounted) context.read<ModelState>().applyCheckResult(result);
  }

  Future<void> _startDownload() async {
    await NativeBridge.instance.startDownload(
      url: _selected.url,
      fileName: _selected.fileName,
    );
  }

  Future<void> _cancelDownload() async {
    await NativeBridge.instance.cancelDownload();
    if (mounted) context.read<ModelState>().setNotDownloaded();
  }

  Future<void> _loadModel() async {
    final modelState = context.read<ModelState>();
    modelState.setLoading();
    try {
      await NativeBridge.instance.loadDownloadedModel(useGpu: _selected.useGpu);
      if (mounted) modelState.setReady();
    } catch (e) {
      if (mounted) modelState.setError(e.toString());
    }
  }

  Future<void> _deleteModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete model?'),
        content: const Text(
            'The model file will be removed from the device. '
            'You will need to download it again to use AI fraud detection.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NativeBridge.instance.deleteModel();
    if (mounted) context.read<ModelState>().setNotDownloaded();
  }

  @override
  Widget build(BuildContext context) {
    final modelState = context.watch<ModelState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Model'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(status: modelState.status),
          const SizedBox(height: 16),

          // ── Main action area ─────────────────────────────────────────
          switch (modelState.status) {
            ModelStatus.notDownloaded || ModelStatus.error =>
              _DownloadForm(
                model: _selected,
                errorMessage: modelState.errorMessage,
                onDownload: _startDownload,
              ),
            ModelStatus.downloading || ModelStatus.paused =>
              _ProgressCard(
                percent: modelState.progressPercent,
                downloaded: modelState.downloadedBytesLabel,
                total: modelState.totalBytesLabel,
                isPaused: modelState.status == ModelStatus.paused,
                onCancel: _cancelDownload,
              ),
            ModelStatus.downloaded =>
              _ReadyToLoadCard(
                modelPath: modelState.modelPath,
                onLoad: _loadModel,
                onDelete: _deleteModel,
              ),
            ModelStatus.loading =>
              const _LoadingCard(),
            ModelStatus.ready =>
              _LoadedCard(
                modelPath: modelState.modelPath,
                onDelete: _deleteModel,
              ),
            ModelStatus.unknown =>
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
          },

        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final ModelStatus status;
  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      ModelStatus.ready    => (Icons.check_circle, 'Model ready — tap Start Chatting', Colors.green),
      ModelStatus.downloaded => (Icons.download_done, 'Downloaded — tap Load to activate', Colors.blue),
      ModelStatus.loading  => (Icons.hourglass_top, 'Loading model into memory…', Colors.orange),
      ModelStatus.downloading || ModelStatus.paused =>
                              (Icons.downloading, 'Downloading…', Colors.blue),
      ModelStatus.error    => (Icons.error_outline, 'Error — see below', Colors.red),
      _                    => (Icons.cloud_download_outlined, 'Model not on device', Colors.grey),
    };

    return Card(
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color, size: 28),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        subtitle: const Text('Gemma 4 on-device via LiteRT'),
      ),
    );
  }
}

class _DownloadForm extends StatelessWidget {
  final _ModelVariant model;
  final String errorMessage;
  final VoidCallback onDownload;

  const _DownloadForm({
    required this.model,
    required this.errorMessage,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.memory),
            title: Text(model.label),
            subtitle: Text(model.sizeLabel),
          ),
        ),
        if (errorMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(errorMessage,
              style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onDownload,
          icon: const Icon(Icons.download),
          label: Text('Download ${model.sizeLabel}'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int percent;
  final String downloaded;
  final String total;
  final bool isPaused;
  final VoidCallback onCancel;

  const _ProgressCard({
    required this.percent,
    required this.downloaded,
    required this.total,
    required this.isPaused,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isPaused ? 'Download paused' : 'Downloading…',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('$percent%',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$downloaded / $total',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              isPaused
                  ? 'Paused — will resume when connectivity is restored.'
                  : 'Download continues even if the app is closed.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyToLoadCard extends StatelessWidget {
  final String modelPath;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  const _ReadyToLoadCard({
    required this.modelPath,
    required this.onLoad,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.download_done, size: 48, color: Colors.blue),
            const SizedBox(height: 12),
            const Text('Model downloaded',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(modelPath,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.memory),
              label: const Text('Load model into memory'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete file'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading model into LiteRT…',
                style: TextStyle(fontSize: 15)),
            SizedBox(height: 4),
            Text('This takes a few seconds on first run.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _LoadedCard extends StatelessWidget {
  final String modelPath;
  final VoidCallback onDelete;

  const _LoadedCard({required this.modelPath, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle, size: 48, color: Colors.green),
            const SizedBox(height: 12),
            const Text('Gemma 4 is ready',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/chat'),
              icon: const Icon(Icons.chat),
              label: const Text('Start Chatting'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove model'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _ModelVariant {
  final String label;
  final String fileName;
  final String sizeLabel;
  final String url;
  final bool useGpu;
  const _ModelVariant({
    required this.label,
    required this.fileName,
    required this.sizeLabel,
    required this.url,
    required this.useGpu,
  });
}
