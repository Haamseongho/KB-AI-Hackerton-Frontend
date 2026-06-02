import 'package:flutter/material.dart';

import '../../domain/meeting_room.dart';
import '../../domain/meeting_status.dart';
import 'status_chip.dart';

class MeetingCard extends StatelessWidget {
  const MeetingCard({
    super.key,
    required this.room,
    required this.onOpen,
    required this.onUpload,
  });

  final MeetingRoom room;
  final VoidCallback onOpen;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RoomIcon(status: room.status),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(room.meetingId),
                        Text(_formatDate(room.createdAt)),
                      ],
                    ),
                  ),
                  StatusChip(status: room.status),
                ],
              ),
              const Divider(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('녹음'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.description_outlined),
                      label: Text('대화록 ${room.segments.length}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onUpload,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('회의록'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}. ${date.month}. ${date.day}. ${_two(date.hour)}:${_two(date.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _RoomIcon extends StatelessWidget {
  const _RoomIcon({required this.status});

  final MeetingStatus status;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      MeetingStatus.recording || MeetingStatus.paused => Icons.graphic_eq,
      MeetingStatus.completed ||
      MeetingStatus.transcriptionCompleted => Icons.check_circle_outline,
      MeetingStatus.generatingMinutes => Icons.pending_actions_outlined,
      MeetingStatus.uploaded => Icons.cloud_done_outlined,
      _ => Icons.groups_2_outlined,
    };

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary),
    );
  }
}
