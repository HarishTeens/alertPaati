import 'package:flutter/foundation.dart';

enum ModelStatus {
  unknown,      // not yet checked
  notDownloaded,
  downloading,
  paused,
  downloaded,   // on disk but not loaded into memory
  loading,      // being loaded into LiteRT
  ready,        // loaded and ready for inference
  error,
}

class ModelState extends ChangeNotifier {
  ModelStatus _status = ModelStatus.unknown;
  int _progressPercent = 0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String _modelPath = '';
  String _errorMessage = '';
  bool _isLoaded = false;

  ModelStatus get status => _status;
  int get progressPercent => _progressPercent;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  String get modelPath => _modelPath;
  String get errorMessage => _errorMessage;
  bool get isLoaded => _isLoaded;

  bool get isDownloading =>
      _status == ModelStatus.downloading || _status == ModelStatus.paused;
  bool get isDownloaded =>
      _status == ModelStatus.downloaded ||
      _status == ModelStatus.loading ||
      _status == ModelStatus.ready;
  bool get isReady => _status == ModelStatus.ready;
  bool get canStartCall => _status == ModelStatus.ready;

  String get downloadedBytesLabel => _formatBytes(_downloadedBytes);
  String get totalBytesLabel => _formatBytes(_totalBytes);

  // Called once on app start from NativeBridge.checkModel()
  void applyCheckResult(Map<String, dynamic> result) {
    final downloaded = result['downloaded'] as bool? ?? false;
    final loaded = result['loaded'] as bool? ?? false;
    _modelPath = result['path'] as String? ?? '';

    if (loaded) {
      _status = ModelStatus.ready;
      _isLoaded = true;
    } else if (downloaded && _modelPath.isNotEmpty) {
      _status = ModelStatus.downloaded;
      _isLoaded = false;
    } else {
      _status = ModelStatus.notDownloaded;
      _isLoaded = false;
    }
    notifyListeners();
  }

  // Called for each event from kavach/downloadProgress EventChannel
  void applyDownloadEvent(Map<String, dynamic> event) {
    final statusStr = event['status'] as String? ?? 'idle';
    _progressPercent = (event['progress'] as int?) ?? _progressPercent;
    _downloadedBytes = (event['downloadedBytes'] as int?) ?? _downloadedBytes;
    _totalBytes = (event['totalBytes'] as int?) ?? _totalBytes;

    switch (statusStr) {
      case 'downloading':
        _status = ModelStatus.downloading;
        _errorMessage = '';
      case 'paused':
        _status = ModelStatus.paused;
      case 'completed':
        _status = ModelStatus.downloaded;
        _progressPercent = 100;
        _modelPath = event['modelPath'] as String? ?? _modelPath;
        _errorMessage = '';
      case 'failed':
        _status = ModelStatus.error;
        _errorMessage = 'Download failed. Check your connection and try again.';
      case 'idle':
        if (_status == ModelStatus.downloading || _status == ModelStatus.paused) {
          _status = ModelStatus.notDownloaded;
        }
    }
    notifyListeners();
  }

  void setLoading() {
    _status = ModelStatus.loading;
    notifyListeners();
  }

  void setReady() {
    _status = ModelStatus.ready;
    _isLoaded = true;
    _errorMessage = '';
    notifyListeners();
  }

  void setError(String message) {
    _status = ModelStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  void setNotDownloaded() {
    _status = ModelStatus.notDownloaded;
    _modelPath = '';
    _isLoaded = false;
    _progressPercent = 0;
    _downloadedBytes = 0;
    _totalBytes = 0;
    notifyListeners();
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
