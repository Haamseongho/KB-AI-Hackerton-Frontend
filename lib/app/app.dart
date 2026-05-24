import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/meetings/data/in_memory_meeting_repository.dart';
import '../features/meetings/data/meeting_api.dart';
import '../features/meetings/presentation/meetings_controller.dart';
import '../features/meetings/presentation/meetings_page.dart';

class VoiceDocApp extends StatefulWidget {
  const VoiceDocApp({super.key});

  @override
  State<VoiceDocApp> createState() => _VoiceDocAppState();
}

class _VoiceDocAppState extends State<VoiceDocApp> {
  late final MeetingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MeetingsController(
      repository: InMemoryMeetingRepository.seeded(),
      api: MeetingApi(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Doc',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: MeetingsPage(controller: _controller),
    );
  }
}
