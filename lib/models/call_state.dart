import 'package:flutter/foundation.dart';
import 'fraud_result.dart';

enum CallStatus { idle, dialing, ringing, active, ended }

enum FraudLevel { safe, suspicious, danger }

class CallState extends ChangeNotifier {
  CallStatus _status = CallStatus.idle;
  String _phoneNumber = '';
  String _callerName = '';
  Duration _duration = Duration.zero;
  FraudResult? _latestFraudResult;
  final List<FraudResult> _fraudHistory = [];
  String _transcript = '';
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isRecording = false;

  CallStatus get status => _status;
  String get phoneNumber => _phoneNumber;
  String get callerName => _callerName;
  Duration get duration => _duration;
  FraudResult? get latestFraudResult => _latestFraudResult;
  List<FraudResult> get fraudHistory => List.unmodifiable(_fraudHistory);
  String get transcript => _transcript;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isRecording => _isRecording;
  bool get isCallActive => _status == CallStatus.active;

  FraudLevel get currentFraudLevel {
    if (_latestFraudResult == null) return FraudLevel.safe;
    return _latestFraudResult!.level;
  }

  void startDialing(String number) {
    _phoneNumber = number;
    _status = CallStatus.dialing;
    _latestFraudResult = null;
    _fraudHistory.clear();
    _transcript = '';
    _duration = Duration.zero;
    notifyListeners();
  }

  void onCallConnected({String callerName = ''}) {
    _status = CallStatus.active;
    _callerName = callerName;
    _isRecording = true;
    notifyListeners();
  }

  void onCallRinging() {
    _status = CallStatus.ringing;
    notifyListeners();
  }

  void onCallEnded() {
    _status = CallStatus.ended;
    _isRecording = false;
    notifyListeners();
  }

  void reset() {
    _status = CallStatus.idle;
    _phoneNumber = '';
    _callerName = '';
    _duration = Duration.zero;
    _latestFraudResult = null;
    _fraudHistory.clear();
    _transcript = '';
    _isMuted = false;
    _isSpeakerOn = false;
    _isRecording = false;
    notifyListeners();
  }

  void updateDuration(Duration d) {
    _duration = d;
    notifyListeners();
  }

  void updateFraudResult(FraudResult result) {
    _latestFraudResult = result;
    _fraudHistory.add(result);
    notifyListeners();
  }

  void appendTranscript(String text) {
    if (_transcript.isNotEmpty) _transcript += ' ';
    _transcript += text;
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    notifyListeners();
  }
}
