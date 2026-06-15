import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/meeting_room.dart';
import '../../domain/meeting_status.dart';
import '../../domain/meeting_workflow.dart';
import 'status_chip.dart';

class MeetingCard extends StatelessWidget {
  const MeetingCard({
    super.key,
    required this.room,
    required this.onOpen,
    required this.onPrimaryAction,
    required this.onDelete,
  });

  final MeetingRoom room;
  final VoidCallback onOpen;
  final VoidCallback onPrimaryAction;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isBatch = room.workflow == MeetingWorkflow.batch;
    final processing = _isProcessing(room.status);
    final completed = room.status == MeetingStatus.completed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusChip(status: room.status),
                        const SizedBox(height: 10),
                        Text(
                          room.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        _MetadataLine(
                          icon: Icons.tag,
                          text: room.meetingId,
                          monospace: true,
                        ),
                        const SizedBox(height: 3),
                        _MetadataLine(
                          icon: Icons.schedule_outlined,
                          text: _formatDate(room.createdAt),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_MeetingCardAction>(
                    tooltip: '회의방 옵션',
                    icon: const Icon(
                      Icons.chevron_right,
                      color: AppTheme.muted,
                    ),
                    onSelected: (action) {
                      if (action == _MeetingCardAction.deleteMeeting) {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _MeetingCardAction.deleteMeeting,
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline),
                            SizedBox(width: 10),
                            Text('회의 삭제'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onPrimaryAction,
                    icon: Icon(_primaryIcon(isBatch, processing, completed)),
                    label: Text(_primaryLabel(isBatch, processing, completed)),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                  if (completed)
                    OutlinedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('전사문'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  if (processing && isBatch)
                    TextButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('상태 확인'),
                    ),
                ],
              ),
              if (processing && isBatch) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      room.batchStatus?.label ?? room.status.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _progressLabel(room.status),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: _progress(room.status),
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: const Color(0xFFE9EEF7),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _isProcessing(MeetingStatus status) {
    return {
      MeetingStatus.uploading,
      MeetingStatus.uploaded,
      MeetingStatus.queued,
      MeetingStatus.transcribing,
      MeetingStatus.summarizing,
    }.contains(status);
  }

  IconData _primaryIcon(bool isBatch, bool processing, bool completed) {
    if (completed) return Icons.visibility_outlined;
    if (processing) return Icons.visibility_outlined;
    return isBatch ? Icons.play_arrow_rounded : Icons.mic_none_rounded;
  }

  String _primaryLabel(bool isBatch, bool processing, bool completed) {
    if (completed) return isBatch ? '결과 보기' : '회의록 보기';
    if (processing) return '진행 보기';
    return isBatch ? '배치 시작' : '회의 시작';
  }

  double _progress(MeetingStatus status) {
    return switch (status) {
      MeetingStatus.uploading => 0.2,
      MeetingStatus.uploaded => 0.35,
      MeetingStatus.queued => 0.45,
      MeetingStatus.transcribing => 0.7,
      MeetingStatus.summarizing => 0.9,
      _ => 0,
    };
  }

  String _progressLabel(MeetingStatus status) {
    return '${(_progress(status) * 100).round()}%';
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${_two(date.month)}.${_two(date.day)} '
        '${_two(date.hour)}:${_two(date.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

enum _MeetingCardAction { deleteMeeting }

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({
    required this.icon,
    required this.text,
    this.monospace = false,
  });

  final IconData icon;
  final String text;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.muted),
        const SizedBox(width: 5),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: monospace ? 'monospace' : null,
            letterSpacing: monospace ? 0.4 : null,
          ),
        ),
      ],
    );
  }
}
