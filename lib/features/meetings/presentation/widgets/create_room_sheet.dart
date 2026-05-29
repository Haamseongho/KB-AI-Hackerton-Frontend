import 'package:flutter/material.dart';

import '../../domain/meeting_type.dart';

class CreateRoomSheet extends StatefulWidget {
  const CreateRoomSheet({super.key, required this.onCreate});

  final Future<void> Function({
    required String title,
    required MeetingType meetingType,
    required String storageType,
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
  String _storageType = 'local_db';
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Create Meeting Room',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Room Title',
                  hintText: 'e.g. AWS Architecture Review',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<MeetingType>(
                initialValue: _meetingType,
                decoration: const InputDecoration(
                  labelText: 'Meeting Type',
                  border: OutlineInputBorder(),
                ),
                items: MeetingType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _meetingType = value);
                },
              ),
              const SizedBox(height: 14),
              Text('Storage', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'local_db',
                    icon: Icon(Icons.storage_outlined),
                    label: Text('Local DB'),
                  ),
                  ButtonSegment(
                    value: 'aws_rds',
                    icon: Icon(Icons.cloud_outlined),
                    label: Text('AWS RDS'),
                  ),
                ],
                selected: {_storageType},
                onSelectionChanged: (value) {
                  setState(() => _storageType = value.first);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Optional Notes',
                  hintText: '녹음 -> 실시간',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              _SchemaPreview(
                title: _titleController.text,
                meetingType: _meetingType,
                storageType: _storageType,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isCreating
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isCreating ? null : _create,
                      icon: const Icon(Icons.add),
                      label: const Text('Create Room'),
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

  Future<void> _create() async {
    setState(() => _isCreating = true);
    await widget.onCreate(
      title: _titleController.text,
      meetingType: _meetingType,
      storageType: _storageType,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }
}

class _SchemaPreview extends StatelessWidget {
  const _SchemaPreview({
    required this.title,
    required this.meetingType,
    required this.storageType,
  });

  final String title;
  final MeetingType meetingType;
  final String storageType;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '{\n'
        '  "room_title": "${title.trim().isEmpty ? 'Untitled Meeting' : title.trim()}",\n'
        '  "meeting_id": "MTG-yyyyMMdd-###",\n'
        '  "status": "ready",\n'
        '  "meeting_type": "${meetingType.value}",\n'
        '  "storage_metadata": {\n'
        '    "type": "$storageType"\n'
        '  }\n'
        '}',
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          height: 1.4,
        ),
      ),
    );
  }
}
