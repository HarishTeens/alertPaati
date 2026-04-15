import 'dart:async';
import 'package:flutter/services.dart';
import '../models/call_state.dart';
import '../models/fraud_result.dart';
import '../models/model_state.dart';

/// Central hub for all Flutter <-> Kotlin communication.
///
/// Channels:
///   kavach/call       – call control (MethodChannel)
///   kavach/fraud      – fraud analysis (MethodChannel)
///   kavach/recording  – audio recording (MethodChannel)
///   kavach/callEvents – real-time call state (EventChannel)
///   kavach/fraudEvents– real-time fraud alerts (EventChannel)
class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  static const _callChannel = MethodChannel('kavach/call');
  static const _fraudChannel = MethodChannel('kavach/fraud');
  static const _recordingChannel = MethodChannel('kavach/recording');
  static const _modelChannel = MethodChannel('kavach/model');
  static const _callEvents = EventChannel('kavach/callEvents');
  static const _fraudEvents = EventChannel('kavach/fraudEvents');
  static const _downloadProgress = EventChannel('kavach/downloadProgress');

  Stream<Map<String, dynamic>>? _callEventStream;
  Stream<Map<String, dynamic>>? _fraudEventStream;
  Stream<Map<String, dynamic>>? _downloadProgressStream;

  // ── Call Events ──────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get callEvents {
    _callEventStream ??= _callEvents
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _callEventStream!;
  }

  // ── Fraud Events ─────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get fraudEvents {
    _fraudEventStream ??= _fraudEvents
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _fraudEventStream!;
  }

  // ── Call Control ─────────────────────────────────────────────────────────

  Future<void> dialNumber(String phoneNumber) async {
    await _callChannel.invokeMethod('dialNumber', {'number': phoneNumber});
  }

  Future<void> endCall() async {
    await _callChannel.invokeMethod('endCall');
  }

  Future<void> setMute(bool muted) async {
    await _callChannel.invokeMethod('setMute', {'muted': muted});
  }

  Future<void> setSpeaker(bool enabled) async {
    await _callChannel.invokeMethod('setSpeaker', {'enabled': enabled});
  }

  Future<bool> requestPhoneAccountPermission() async {
    final result =
        await _callChannel.invokeMethod<bool>('requestPhoneAccount');
    return result ?? false;
  }

  // ── Recording ────────────────────────────────────────────────────────────

  Future<void> startRecording() async {
    await _recordingChannel.invokeMethod('startRecording');
  }

  Future<String?> stopRecordingAndGetPath() async {
    final path =
        await _recordingChannel.invokeMethod<String>('stopRecording');
    return path;
  }

  // ── Fraud Engine ─────────────────────────────────────────────────────────

  /// Analyze [transcript] text for fraud signals using on-device Gemma.
  Future<FraudResult> analyzeTranscript(String transcript) async {
    final result = await _fraudChannel.invokeMethod<Map>(
      'analyzeTranscript',
      {'transcript': transcript},
    );
    if (result == null) return FraudResult.safe();
    return FraudResult.fromMap(Map<String, dynamic>.from(result));
  }

  /// Analyze a PCM audio file at [filePath] (records → STT → Gemma).
  Future<FraudResult> analyzeAudioFile(String filePath) async {
    final result = await _fraudChannel.invokeMethod<Map>(
      'analyzeAudioFile',
      {'path': filePath},
    );
    if (result == null) return FraudResult.safe();
    return FraudResult.fromMap(Map<String, dynamic>.from(result));
  }

  Future<bool> isModelLoaded() async {
    final loaded =
        await _fraudChannel.invokeMethod<bool>('isModelLoaded');
    return loaded ?? false;
  }

  Future<void> loadModel(String modelPath) async {
    await _fraudChannel.invokeMethod('loadModel', {'path': modelPath});
  }

  // ── Model Download ────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get downloadProgress {
    _downloadProgressStream ??= _downloadProgress
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _downloadProgressStream!;
  }

  Future<Map<String, dynamic>> checkModel() async {
    final result = await _modelChannel.invokeMethod<Map>('checkModel');
    return result == null ? {} : Map<String, dynamic>.from(result);
  }

  /// [url] must be a direct HTTPS link to the .tflite file.
  /// [authToken] is an optional HuggingFace/Kaggle API token.
  Future<void> startDownload({
    required String url,
    String fileName = 'gemma-4-1b-it-cpu-int8.tflite',
    String? authToken,
  }) async {
    await _modelChannel.invokeMethod('startDownload', {
      'url': url,
      'fileName': fileName,
      if (authToken case final String token) 'authToken': token,
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

  /// Subscribes to download progress events and applies them to [modelState].
  StreamSubscription<Map<String, dynamic>> bindDownloadProgress(
      ModelState modelState) {
    return downloadProgress.listen(modelState.applyDownloadEvent);
  }

  // ── Overlay ───────────────────────────────────────────────────────────────

  Future<void> showFraudOverlay(FraudResult result) async {
    await _callChannel.invokeMethod('showOverlay', result.toMap());
  }

  Future<void> hideOverlay() async {
    await _callChannel.invokeMethod('hideOverlay');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Subscribes to call events and updates [callState] accordingly.
  StreamSubscription<Map<String, dynamic>> bindCallState(
      CallState callState) {
    return callEvents.listen((event) {
      final type = event['type'] as String?;
      switch (type) {
        case 'dialing':
          callState.startDialing(event['number'] as String? ?? '');
        case 'ringing':
          callState.onCallRinging();
        case 'active':
          callState.onCallConnected(
              callerName: event['name'] as String? ?? '');
        case 'ended':
          callState.onCallEnded();
        case 'duration':
          final ms = event['ms'] as int? ?? 0;
          callState.updateDuration(Duration(milliseconds: ms));
        case 'transcript':
          callState.appendTranscript(event['text'] as String? ?? '');
      }
    });
  }

  /// Subscribes to fraud events and updates [callState] accordingly.
  StreamSubscription<Map<String, dynamic>> bindFraudEvents(
      CallState callState) {
    return fraudEvents.listen((event) {
      final result = FraudResult.fromMap(event);
      callState.updateFraudResult(result);
    });
  }
}
