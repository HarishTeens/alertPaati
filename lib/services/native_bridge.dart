import 'dart:async';
import 'package:flutter/services.dart';
import '../models/model_state.dart';

class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  static const _modelChannel = MethodChannel('kavach/model');
  static const _chatChannel = MethodChannel('kavach/chat');
  static const _downloadProgress = EventChannel('kavach/downloadProgress');
  static const _chatTokens = EventChannel('kavach/chatStream');

  Stream<Map<String, dynamic>>? _downloadProgressStream;
  Stream<Map<String, dynamic>>? _chatTokenStream;

  Stream<Map<String, dynamic>> get downloadProgress {
    _downloadProgressStream ??= _downloadProgress
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _downloadProgressStream!;
  }

  Stream<Map<String, dynamic>> get chatTokenStream {
    _chatTokenStream ??= _chatTokens
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _chatTokenStream!;
  }

  StreamSubscription<Map<String, dynamic>> bindDownloadProgress(
      ModelState modelState) {
    return downloadProgress.listen(modelState.applyDownloadEvent);
  }

  Future<Map<String, dynamic>> checkModel() async {
    final result = await _modelChannel.invokeMethod<Map>('checkModel');
    return result == null ? {} : Map<String, dynamic>.from(result);
  }

  Future<void> startDownload({
    required String url,
    String fileName = 'gemma-4-E2B-it.litertlm',
  }) async {
    await _modelChannel.invokeMethod('startDownload', {
      'url': url,
      'fileName': fileName,
    });
  }

  Future<void> cancelDownload() async {
    await _modelChannel.invokeMethod('cancelDownload');
  }

  Future<void> deleteModel() async {
    await _modelChannel.invokeMethod('deleteModel');
  }

  Future<void> loadDownloadedModel({bool useGpu = false}) async {
    await _modelChannel.invokeMethod('loadModel', {'useGpu': useGpu});
  }

  /// Starts generation and returns immediately. Tokens arrive via [chatTokenStream].
  Future<void> startChat(String message) async {
    await _chatChannel.invokeMethod('startChat', {'message': message});
  }

  Future<void> resetConversation() async {
    await _chatChannel.invokeMethod('resetConversation');
  }
}
