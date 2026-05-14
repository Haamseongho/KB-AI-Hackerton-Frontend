import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const VoiceDocApp());
}

class VoiceDocApp extends StatelessWidget {
  const VoiceDocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Doc',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6F5E)),
        useMaterial3: true,
      ),
      home: const MeetingsPage(),
    );
  }
}

class ApiConfig {
  const ApiConfig._();

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}

enum MeetingType {
  oneOnOne('one_on_one', '1:1'),
  small('small', '소규모'),
  medium('medium', '중규모'),
  unknown('unknown', '미정');

  const MeetingType(this.value, this.label);

  final String value;
  final String label;
}

enum MeetingStatus {
  created('created', '생성됨'),
  uploaded('uploaded', '업로드됨'),
  queued('queued', '대기 중'),
  transcribing('transcribing', '음성 인식 중'),
  summarizing('summarizing', '회의록 생성 중'),
  completed('completed', '완료'),
  failed('failed', '실패');

  const MeetingStatus(this.value, this.label);

  final String value;
  final String label;

  static MeetingStatus fromJson(String? value) {
    return MeetingStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => MeetingStatus.created,
    );
  }
}

enum JobStatus {
  queued('queued', '대기 중'),
  running('running', '처리 중'),
  completed('completed', '완료'),
  failed('failed', '실패');

  const JobStatus(this.value, this.label);

  final String value;
  final String label;

  static JobStatus fromJson(String? value) {
    return JobStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => JobStatus.queued,
    );
  }
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    required this.meetingType,
    required this.status,
    this.summary,
    this.errorMessage,
  });

  final String id;
  final String title;
  final MeetingType meetingType;
  final MeetingStatus status;
  final String? summary;
  final String? errorMessage;

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'] as String,
      title: json['title'] as String? ?? '제목 없음',
      meetingType: MeetingType.values.firstWhere(
        (type) => type.value == json['meeting_type'],
        orElse: () => MeetingType.unknown,
      ),
      status: MeetingStatus.fromJson(json['status'] as String?),
      summary: json['summary'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class UploadUrl {
  const UploadUrl({
    required this.uploadUrl,
    required this.s3Key,
    required this.expiresIn,
  });

  final String uploadUrl;
  final String s3Key;
  final int expiresIn;

  factory UploadUrl.fromJson(Map<String, dynamic> json) {
    return UploadUrl(
      uploadUrl: json['upload_url'] as String,
      s3Key: json['s3_key'] as String,
      expiresIn: json['expires_in'] as int? ?? 0,
    );
  }
}

class StartJobResponse {
  const StartJobResponse({
    required this.meetingId,
    required this.jobId,
    required this.status,
  });

  final String meetingId;
  final String jobId;
  final JobStatus status;

  factory StartJobResponse.fromJson(Map<String, dynamic> json) {
    return StartJobResponse(
      meetingId: json['meeting_id'] as String,
      jobId: json['job_id'] as String,
      status: JobStatus.fromJson(json['status'] as String?),
    );
  }
}

class Job {
  const Job({
    required this.id,
    required this.meetingId,
    required this.status,
    this.errorMessage,
  });

  final String id;
  final String meetingId;
  final JobStatus status;
  final String? errorMessage;

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'] as String,
      meetingId: json['meeting_id'] as String,
      status: JobStatus.fromJson(json['status'] as String?),
      errorMessage: json['error_message'] as String?,
    );
  }
}

class MeetingResult {
  const MeetingResult({
    required this.meetingId,
    required this.status,
    required this.title,
    this.summary,
    this.decisions = const [],
    this.actionItems = const [],
  });

  final String meetingId;
  final MeetingStatus status;
  final String title;
  final String? summary;
  final List<String> decisions;
  final List<ActionItem> actionItems;

  factory MeetingResult.fromJson(Map<String, dynamic> json) {
    final actionItems = json['action_items'];
    final decisions = json['decisions'];

    return MeetingResult(
      meetingId: json['meeting_id'] as String,
      status: MeetingStatus.fromJson(json['status'] as String?),
      title: json['title'] as String? ?? '회의록',
      summary: json['summary'] as String?,
      decisions: decisions is List
          ? decisions.whereType<String>().toList(growable: false)
          : const [],
      actionItems: actionItems is List
          ? actionItems
                .whereType<Map<String, dynamic>>()
                .map(ActionItem.fromJson)
                .toList(growable: false)
          : const [],
    );
  }
}

class ActionItem {
  const ActionItem({
    required this.owner,
    required this.task,
    required this.dueDate,
  });

  final String owner;
  final String task;
  final String dueDate;

  factory ActionItem.fromJson(Map<String, dynamic> json) {
    return ActionItem(
      owner: json['owner'] as String? ?? '담당자 미정',
      task: json['task'] as String? ?? '',
      dueDate: json['due_date'] as String? ?? '미정',
    );
  }
}

class VoiceDocApi {
  VoiceDocApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = Uri.parse(baseUrl ?? ApiConfig.baseUrl);

  final http.Client _client;
  final Uri _baseUrl;

  Future<Meeting> createMeeting({
    required String title,
    required MeetingType meetingType,
  }) async {
    final response = await _post(
      '/meetings',
      body: {'title': title, 'meeting_type': meetingType.value},
    );
    return Meeting.fromJson(response);
  }

  Future<UploadUrl> createUploadUrl({
    required String meetingId,
    required String fileExtension,
    required String contentType,
  }) async {
    final response = await _post(
      '/meetings/$meetingId/upload-url',
      body: {'file_extension': fileExtension, 'content_type': contentType},
    );
    return UploadUrl.fromJson(response);
  }

  Future<void> uploadToS3({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final response = await _client
        .put(
          Uri.parse(uploadUrl),
          headers: {'Content-Type': contentType},
          body: bytes,
        )
        .timeout(const Duration(minutes: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('S3 upload failed', statusCode: response.statusCode);
    }
  }

  Future<StartJobResponse> startMeeting(String meetingId) async {
    final response = await _post('/meetings/$meetingId/start');
    return StartJobResponse.fromJson(response);
  }

  Future<Meeting> getMeeting(String meetingId) async {
    final response = await _get('/meetings/$meetingId');
    return Meeting.fromJson(response);
  }

  Future<Job> getJob(String jobId) async {
    final response = await _get('/jobs/$jobId');
    return Job.fromJson(response);
  }

  Future<MeetingResult> getResult(String meetingId) async {
    final response = await _get('/meetings/$meetingId/result');
    return MeetingResult.fromJson(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client
        .get(_baseUrl.resolve(path))
        .timeout(const Duration(seconds: 15));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _client
        .post(
          _baseUrl.resolve(path),
          headers: {'Content-Type': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isEmpty ? 'Request failed' : response.body,
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const ApiException('Unexpected API response');
  }
}

class MeetingsController extends ChangeNotifier {
  MeetingsController({VoiceDocApi? api}) : _api = api ?? VoiceDocApi();

  final VoiceDocApi _api;
  final List<Meeting> meetings = [];

  MeetingType selectedType = MeetingType.unknown;
  Meeting? currentMeeting;
  MeetingResult? result;
  String? jobId;
  String? selectedFileName;
  String statusMessage = '회의 음성 파일을 선택해 주세요.';
  String? errorMessage;
  bool isBusy = false;

  Timer? _pollingTimer;
  bool _isPollingRequestInFlight = false;

  Future<void> selectAndStart(String title) async {
    if (isBusy) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _setError('파일을 읽을 수 없습니다. 다른 파일을 선택해 주세요.');
      return;
    }

    selectedFileName = file.name;
    await _runUploadFlow(
      title: title.trim().isEmpty ? '새 회의' : title.trim(),
      fileName: file.name,
      bytes: bytes,
    );
  }

  Future<void> retryStartOrPolling() async {
    final meeting = currentMeeting;
    if (meeting == null || isBusy) return;

    errorMessage = null;
    isBusy = true;
    notifyListeners();

    try {
      if (jobId == null && meeting.status != MeetingStatus.completed) {
        await _startMeetingJob(meeting.id);
      } else {
        _startPolling(meeting.id, jobId: jobId);
      }
    } catch (error) {
      _setError(_userMessage(error));
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> openMeeting(Meeting meeting) async {
    currentMeeting = meeting;
    result = null;
    errorMessage = null;
    statusMessage = _meetingStatusMessage(meeting.status);
    notifyListeners();

    if (meeting.status == MeetingStatus.completed) {
      await _loadResult(meeting.id);
    } else if (meeting.status != MeetingStatus.failed) {
      _startPolling(meeting.id);
    }
  }

  Future<void> _runUploadFlow({
    required String title,
    required String fileName,
    required Uint8List bytes,
  }) async {
    _stopPolling();
    errorMessage = null;
    result = null;
    jobId = null;
    isBusy = true;
    statusMessage = '회의를 생성하는 중입니다.';
    notifyListeners();

    try {
      final meeting = await _api.createMeeting(
        title: title,
        meetingType: selectedType,
      );
      _upsertMeeting(meeting);
      currentMeeting = meeting;
      statusMessage = '업로드 주소를 발급받는 중입니다.';
      notifyListeners();

      final contentType = _contentTypeFor(fileName);
      final uploadUrl = await _api.createUploadUrl(
        meetingId: meeting.id,
        fileExtension: _extensionFor(fileName),
        contentType: contentType,
      );

      statusMessage = '음성 파일을 업로드하는 중입니다.';
      notifyListeners();
      await _api.uploadToS3(
        uploadUrl: uploadUrl.uploadUrl,
        bytes: bytes,
        contentType: contentType,
      );

      await _startMeetingJob(meeting.id);
    } catch (error) {
      _setError(_userMessage(error));
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _startMeetingJob(String meetingId) async {
    statusMessage = '회의록 생성 작업을 시작하는 중입니다.';
    notifyListeners();

    try {
      final started = await _api.startMeeting(meetingId);
      jobId = started.jobId;
      statusMessage = '작업이 대기열에 등록되었습니다.';
      _startPolling(meetingId, jobId: started.jobId);
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        statusMessage = '이미 진행 중인 작업을 이어서 확인합니다.';
        _startPolling(meetingId);
        return;
      }
      rethrow;
    }
  }

  void _startPolling(String meetingId, {String? jobId}) {
    _stopPolling();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _pollOnce(meetingId, jobId: jobId);
    });
    unawaited(_pollOnce(meetingId, jobId: jobId));
  }

  Future<void> _pollOnce(String meetingId, {String? jobId}) async {
    if (_isPollingRequestInFlight) return;
    _isPollingRequestInFlight = true;

    try {
      if (jobId != null) {
        final job = await _api.getJob(jobId);
        statusMessage = job.status.label;
        if (job.status == JobStatus.failed) {
          _stopPolling();
          _setError(job.errorMessage ?? '작업 처리에 실패했습니다.');
          return;
        }
      }

      final meeting = await _api.getMeeting(meetingId);
      _upsertMeeting(meeting);
      currentMeeting = meeting;
      statusMessage = _meetingStatusMessage(meeting.status);
      notifyListeners();

      if (meeting.status == MeetingStatus.completed) {
        _stopPolling();
        await _loadResult(meeting.id);
      } else if (meeting.status == MeetingStatus.failed) {
        _stopPolling();
        _setError(meeting.errorMessage ?? '회의록 생성에 실패했습니다.');
      }
    } catch (error) {
      _stopPolling();
      _setError(_userMessage(error));
    } finally {
      _isPollingRequestInFlight = false;
    }
  }

  Future<void> _loadResult(String meetingId) async {
    statusMessage = '결과를 불러오는 중입니다.';
    notifyListeners();

    try {
      final loaded = await _api.getResult(meetingId);
      result = loaded.status == MeetingStatus.completed ? loaded : null;
      statusMessage = loaded.status == MeetingStatus.completed
          ? '회의록이 준비되었습니다.'
          : _meetingStatusMessage(loaded.status);
      notifyListeners();
    } catch (error) {
      _setError(_userMessage(error));
    }
  }

  void _upsertMeeting(Meeting meeting) {
    final index = meetings.indexWhere((item) => item.id == meeting.id);
    if (index == -1) {
      meetings.insert(0, meeting);
    } else {
      meetings[index] = meeting;
    }
  }

  void _setError(String message) {
    errorMessage = message;
    statusMessage = message;
    notifyListeners();
  }

  String _meetingStatusMessage(MeetingStatus status) {
    return switch (status) {
      MeetingStatus.created => '회의가 생성되었습니다.',
      MeetingStatus.uploaded => '업로드가 완료되었습니다.',
      MeetingStatus.queued => '작업이 대기 중입니다.',
      MeetingStatus.transcribing => '음성을 텍스트로 변환하고 있습니다.',
      MeetingStatus.summarizing => '회의록을 생성하고 있습니다.',
      MeetingStatus.completed => '회의록이 준비되었습니다.',
      MeetingStatus.failed => '처리에 실패했습니다.',
    };
  }

  String _userMessage(Object error) {
    if (error is TimeoutException) {
      return '요청 시간이 초과되었습니다. 백엔드와 worker 상태를 확인해 주세요.';
    }
    if (error is ApiException) {
      final statusCode = error.statusCode;
      if (statusCode != null && statusCode >= 500) {
        return '서버 처리 중 오류가 발생했습니다.';
      }
      return switch (statusCode) {
        404 => '회의를 찾을 수 없습니다.',
        409 => '이미 진행 중인 작업입니다. 상태 확인을 이어갑니다.',
        _ => '요청에 실패했습니다. 입력과 서버 상태를 확인해 주세요.',
      };
    }
    return 'API 서버에 연결할 수 없습니다. ${ApiConfig.baseUrl} 상태를 확인해 주세요.';
  }

  String _extensionFor(String fileName) {
    final parts = fileName.split('.');
    if (parts.length < 2) return 'm4a';
    return parts.last.toLowerCase();
  }

  String _contentTypeFor(String fileName) {
    return switch (_extensionFor(fileName)) {
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'm4a' => 'audio/mp4',
      'mp4' => 'audio/mp4',
      'aac' => 'audio/aac',
      _ => 'application/octet-stream',
    };
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isPollingRequestInFlight = false;
  }
}

class MeetingsPage extends StatefulWidget {
  const MeetingsPage({super.key});

  @override
  State<MeetingsPage> createState() => _MeetingsPageState();
}

class _MeetingsPageState extends State<MeetingsPage> {
  late final MeetingsController _controller;
  final _titleController = TextEditingController(text: '주간 회의');

  @override
  void initState() {
    super.initState();
    _controller = MeetingsController()..addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Doc'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                ApiConfig.baseUrl,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('회의 음성 업로드', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '회의 제목',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<MeetingType>(
            segments: MeetingType.values
                .map(
                  (type) => ButtonSegment(value: type, label: Text(type.label)),
                )
                .toList(growable: false),
            selected: {_controller.selectedType},
            onSelectionChanged: _controller.isBusy
                ? null
                : (selected) {
                    setState(() {
                      _controller.selectedType = selected.first;
                    });
                  },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _controller.isBusy
                ? null
                : () => _controller.selectAndStart(_titleController.text),
            icon: const Icon(Icons.upload_file),
            label: const Text('음성 파일 선택 및 업로드'),
          ),
          if (_controller.selectedFileName != null) ...[
            const SizedBox(height: 8),
            Text('선택 파일: ${_controller.selectedFileName}'),
          ],
          const SizedBox(height: 20),
          _StatusPanel(controller: _controller),
          const SizedBox(height: 24),
          Text('회의 목록', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_controller.meetings.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('아직 생성된 회의가 없습니다.'),
            )
          else
            ..._controller.meetings.map(
              (meeting) => Card(
                child: ListTile(
                  title: Text(meeting.title),
                  subtitle: Text(meeting.status.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _controller.openMeeting(meeting),
                ),
              ),
            ),
          const SizedBox(height: 24),
          _ResultPanel(controller: _controller),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.controller});

  final MeetingsController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (controller.isBusy)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  controller.errorMessage == null
                      ? Icons.info_outline
                      : Icons.error_outline,
                  color: controller.errorMessage == null
                      ? colorScheme.primary
                      : colorScheme.error,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  controller.statusMessage,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          if (controller.errorMessage != null &&
              controller.currentMeeting != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.isBusy
                  ? null
                  : controller.retryStartOrPolling,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 확인'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.controller});

  final MeetingsController controller;

  @override
  Widget build(BuildContext context) {
    final meeting = controller.currentMeeting;
    final result = controller.result;

    if (meeting == null) {
      return const SizedBox.shrink();
    }

    if (meeting.status != MeetingStatus.completed || result == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('현재 회의', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(meeting.title),
            subtitle: Text(meeting.status.label),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(result.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(result.summary ?? '요약 내용이 없습니다.'),
        const SizedBox(height: 20),
        Text('결정 사항', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (result.decisions.isEmpty)
          const Text('등록된 결정 사항이 없습니다.')
        else
          ...result.decisions.map(
            (decision) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(decision),
            ),
          ),
        const SizedBox(height: 16),
        Text('액션 아이템', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (result.actionItems.isEmpty)
          const Text('등록된 액션 아이템이 없습니다.')
        else
          ...result.actionItems.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.task_alt),
              title: Text(item.task),
              subtitle: Text('${item.owner} · ${item.dueDate}'),
            ),
          ),
      ],
    );
  }
}
