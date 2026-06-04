import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/meetings/data/meeting_api.dart';
import '../features/meetings/data/sqlite_meeting_repository.dart';
import '../features/meetings/domain/meeting_repository.dart';
import '../features/meetings/presentation/meetings_controller.dart';
import '../features/meetings/presentation/meetings_page.dart';

class VoiceDocApp extends StatefulWidget {
  const VoiceDocApp({super.key, this.repository, this.api});

  final MeetingRepository? repository;
  final MeetingApi? api;

  @override
  State<VoiceDocApp> createState() => _VoiceDocAppState();
}

class _VoiceDocAppState extends State<VoiceDocApp> {
  late final MeetingsController _controller;
  late final MeetingRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SqliteMeetingRepository();
    _controller = MeetingsController(
      repository: _repository,
      api: widget.api ?? MeetingApi(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    final repository = _repository;
    if (repository is SqliteMeetingRepository) {
      repository.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceDoc',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: MeetingsPage(controller: _controller),
    );
  }
}
