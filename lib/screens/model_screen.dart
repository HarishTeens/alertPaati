import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/model_state.dart';
import '../services/native_bridge.dart';

// Raw .bin model files — compatible with MediaPipe LlmInference.setModelPath().
// Accept terms at huggingface.co/google/gemma-3-1b-it-litert-preview first.
const _kModelVariants = [
  _ModelVariant(
    label: 'Gemma 3 — 1B int8 (CPU, recommended)',
    fileName: 'gemma-3-1b-it-cpu-int8.bin',
    sizeLabel: '~1.3 GB',
    url: 'https://huggingface.co/google/gemma-3-1b-it-litert-preview'
        '/resolve/main/gemma-3-1b-it-cpu-int8.bin',
    useGpu: false,
  ),
  _ModelVariant(
    label: 'Gemma 3 — 4B int4 (CPU, higher accuracy)',
    fileName: 'gemma-3-4b-it-cpu-int4.bin',
    sizeLabel: '~2.8 GB',
    url: 'https://huggingface.co/google/gemma-3-4b-it-litert-preview'
        '/resolve/main/gemma-3-4b-it-cpu-int4.bin',
    useGpu: false,
  ),
  _ModelVariant(
    label: 'Gemma 3 — 1B int8 (GPU)',
    fileName: 'gemma-3-1b-it-gpu-int8.bin',
    sizeLabel: '~1.3 GB',
    url: 'https://huggingface.co/google/gemma-3-1b-it-litert-preview'
        '/resolve/main/gemma-3-1b-it-gpu-int8.bin',
    useGpu: true,
  ),
];

class ModelScreen extends StatefulWidget {
  const ModelScreen({super.key});

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  final _tokenController = TextEditingController();
  _ModelVariant _selected = _kModelVariants.first;
  bool _showToken = false;
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
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final result = await NativeBridge.instance.checkModel();
    if (mounted) context.read<ModelState>().applyCheckResult(result);
  }

  Future<void> _startDownload() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showTokenRequiredSnack();
      return;
    }
    await NativeBridge.instance.startDownload(
      url: _selected.url,
      fileName: _selected.fileName,
      authToken: token,
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

  void _showTokenRequiredSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Paste your HuggingFace token to authenticate the download.'),
      ),
    );
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
                variants: _kModelVariants,
                selected: _selected,
                tokenController: _tokenController,
                showToken: _showToken,
                errorMessage: modelState.errorMessage,
                onVariantChanged: (v) => setState(() => _selected = v),
                onToggleToken: () => setState(() => _showToken = !_showToken),
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

          const SizedBox(height: 24),
          const _HowToGetTokenCard(),
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
      ModelStatus.ready    => (Icons.check_circle, 'Model ready — AI fraud detection active', Colors.green),
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
  final List<_ModelVariant> variants;
  final _ModelVariant selected;
  final TextEditingController tokenController;
  final bool showToken;
  final String errorMessage;
  final ValueChanged<_ModelVariant> onVariantChanged;
  final VoidCallback onToggleToken;
  final VoidCallback onDownload;

  const _DownloadForm({
    required this.variants,
    required this.selected,
    required this.tokenController,
    required this.showToken,
    required this.errorMessage,
    required this.onVariantChanged,
    required this.onToggleToken,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Model variant picker
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select model variant',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                RadioGroup<_ModelVariant>(
                  groupValue: selected,
                  onChanged: (val) { if (val != null) onVariantChanged(val); },
                  child: Column(
                    children: variants.map((v) => RadioListTile<_ModelVariant>(
                      title: Text(v.label),
                      subtitle: Text(v.sizeLabel,
                          style: const TextStyle(fontSize: 12)),
                      value: v,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // HuggingFace token input
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HuggingFace API token',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Required to download Gemma (gated model). '
                  'Get yours at huggingface.co/settings/tokens',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tokenController,
                  obscureText: !showToken,
                  decoration: InputDecoration(
                    hintText: 'hf_xxxxxxxxxxxxxxxxxxxx',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(showToken ? Icons.visibility_off : Icons.visibility),
                      onPressed: onToggleToken,
                    ),
                  ),
                ),
              ],
            ),
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
          label: Text('Download ${selected.sizeLabel}'),
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
            const Icon(Icons.verified_user, size: 48, color: Colors.green),
            const SizedBox(height: 12),
            const Text('Gemma 4 is active',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green)),
            const SizedBox(height: 4),
            const Text(
                'AI fraud detection will run on every call.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 20),
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

class _HowToGetTokenCard extends StatelessWidget {
  const _HowToGetTokenCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.help_outline),
        title: const Text('How to get a HuggingFace token'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _step('1', 'Create a free account at huggingface.co'),
                _step('2', 'Go to huggingface.co/google/gemma-4-1b-it-litert-preview and accept the Gemma terms of use.'),
                _step('3', 'Go to huggingface.co/settings/tokens and create a new Read token.'),
                _step('4', 'Paste the token (starts with hf_…) in the field above and tap Download.'),
                const SizedBox(height: 8),
                const Text(
                  'The model file (~1.3 GB) is saved to the app\'s private storage. '
                  'The download resumes automatically if interrupted.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 11,
              child: Text(n, style: const TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
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
