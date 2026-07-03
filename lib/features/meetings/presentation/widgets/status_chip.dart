import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/meeting_status.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final MeetingStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MeetingStatus.ready => Colors.amber.shade700,
      MeetingStatus.created ||
      MeetingStatus.uploadUrlIssued ||
      MeetingStatus.queued => Colors.amber.shade700,
      MeetingStatus.uploading ||
      MeetingStatus.orchestrationStarting ||
      MeetingStatus.orchestrationStarted => Colors.indigo.shade700,
      MeetingStatus.recording => Colors.red.shade600,
      MeetingStatus.paused => Colors.deepOrange.shade700,
      MeetingStatus.savingRecording => Colors.indigo.shade700,
      MeetingStatus.transcribing => Colors.green.shade700,
      MeetingStatus.transcriptionCompleted ||
      MeetingStatus.completed => Colors.blue.shade700,
      MeetingStatus.uploaded => Colors.green.shade700,
      MeetingStatus.summaryQueued ||
      MeetingStatus.summarizing ||
      MeetingStatus.generatingMinutes => Colors.indigo.shade700,
      MeetingStatus.failed => Colors.red.shade800,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 6),
            Text(
              status.label,
              style: const TextStyle(
                color: AppTheme.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
