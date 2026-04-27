import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'speak_screen.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gemma 4'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
              Tab(icon: Icon(Icons.mic_none), text: 'Speak'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ChatScreen(),
            SpeakScreen(),
          ],
        ),
      ),
    );
  }
}
