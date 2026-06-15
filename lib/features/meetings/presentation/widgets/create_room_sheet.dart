import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/meeting_type.dart';
import '../../domain/meeting_workflow.dart';

class CreateRoomSheet extends StatefulWidget {
  const CreateRoomSheet({super.key, required this.onCreate});

  final Future<void> Function({
    required String title,
    required MeetingType meetingType,
    required String workflowType,
    String? notes,
  })
  onCreate;

  @override
  State<CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<CreateRoomSheet> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  MeetingType _meetingType = MeetingType.general;
  MeetingWorkflow _workflow = MeetingWorkflow.realtime;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_onTitleChanged)
      ..dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onTitleChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final canCreate = _titleController.text.trim().isNotEmpty && !_isCreating;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '새 회의실 만들기',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _isCreating
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _GeneratedIdCard(id: _previewMeetingId()),
              const SizedBox(height: 18),
              const _FieldLabel('회의실 이름', required: true),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(hintText: '예: Q2 제품 로드맵 검토'),
              ),
              const SizedBox(height: 18),
              const _FieldLabel('작업 유형'),
              const SizedBox(height: 8),
              Row(
                children: MeetingWorkflow.values
                    .map((workflow) {
                      final selected = workflow == _workflow;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: workflow == MeetingWorkflow.realtime ? 8 : 0,
                          ),
                          child: _WorkflowButton(
                            workflow: workflow,
                            selected: selected,
                            onTap: () => setState(() => _workflow = workflow),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
              const _FieldLabel('회의 규모'),
              const SizedBox(height: 8),
              DropdownButtonFormField<MeetingType>(
                initialValue: _meetingType,
                items: MeetingType.values
                    .where((type) => type != MeetingType.unknown)
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _meetingType = value);
                },
              ),
              const SizedBox(height: 18),
              const _FieldLabel('메모', optional: true),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                minLines: 3,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '회의 관련 메모를 입력하세요'),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isCreating
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canCreate ? _create : null,
                      child: Text(_isCreating ? '생성 중' : '생성하기'),
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

  String _previewMeetingId() {
    final now = DateTime.now();
    return 'MTG-${now.year}${_two(now.month)}${_two(now.day)}-###';
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  Future<void> _create() async {
    setState(() => _isCreating = true);
    await widget.onCreate(
      title: _titleController.text,
      meetingType: _meetingType,
      workflowType: _workflow.value,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }
}

class _GeneratedIdCard extends StatelessWidget {
  const _GeneratedIdCard({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFC),
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.tag, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('자동 생성 ID', style: Theme.of(context).textTheme.bodySmall),
              Text(
                id,
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkflowButton extends StatelessWidget {
  const _WorkflowButton({
    required this.workflow,
    required this.selected,
    required this.onTap,
  });

  final MeetingWorkflow workflow;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? AppTheme.primary : AppTheme.ink,
        backgroundColor: selected
            ? AppTheme.primary.withValues(alpha: 0.06)
            : Colors.white,
        side: BorderSide(
          color: selected ? AppTheme.primary : AppTheme.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Text(
        workflow == MeetingWorkflow.realtime ? '🔴 실시간 STT' : '📦 배치 전사',
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.required = false, this.optional = false});

  final String text;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Colors.red),
            ),
          if (optional)
            const TextSpan(
              text: ' (선택)',
              style: TextStyle(
                color: AppTheme.muted,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
      style: Theme.of(context).textTheme.labelLarge,
    );
  }
}
