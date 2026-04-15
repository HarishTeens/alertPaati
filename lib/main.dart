import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/call_state.dart';
import 'models/model_state.dart';
import 'services/native_bridge.dart';
import 'screens/dialler_screen.dart';
import 'screens/active_call_screen.dart';
import 'screens/debrief_screen.dart';
import 'screens/model_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CallState()),
        ChangeNotifierProvider(create: (_) => ModelState()),
      ],
      child: const KavachApp(),
    ),
  );
}

class KavachApp extends StatefulWidget {
  const KavachApp({super.key});

  @override
  State<KavachApp> createState() => _KavachAppState();
}

class _KavachAppState extends State<KavachApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final StreamSubscription<Map<String, dynamic>> _callSub;
  late final StreamSubscription<Map<String, dynamic>> _fraudSub;

  @override
  void initState() {
    super.initState();
    final callState = Provider.of<CallState>(context, listen: false);
    _callSub = NativeBridge.instance.bindCallState(callState);
    _fraudSub = NativeBridge.instance.bindFraudEvents(callState);

    // Navigate based on call state changes.
    callState.addListener(() => _onCallStateChanged(callState));
  }

  void _onCallStateChanged(CallState cs) {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    switch (cs.status) {
      case CallStatus.dialing:
      case CallStatus.ringing:
      case CallStatus.active:
        nav.pushNamedAndRemoveUntil('/call', (r) => r.settings.name == '/');
      case CallStatus.ended:
        nav.pushNamedAndRemoveUntil(
            '/debrief', (r) => r.settings.name == '/');
      case CallStatus.idle:
        nav.popUntil((r) => r.isFirst);
    }
  }

  @override
  void dispose() {
    _callSub.cancel();
    _fraudSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'KAVACH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (_) => const DiallerScreen(),
        '/call': (_) => const ActiveCallScreen(),
        '/debrief': (_) => const DebriefScreen(),
        '/model': (_) => const ModelScreen(),
      },
    );
  }
}
