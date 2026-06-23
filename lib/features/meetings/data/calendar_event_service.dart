import 'package:flutter/services.dart';

import '../../../core/errors/app_exception.dart';

class CalendarEventService {
  CalendarEventService({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.kbds.aihackathon.voicedoc/calendar');

  final MethodChannel _channel;

  Future<String?> addEvent({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String? notes,
    bool allDay = true,
  }) async {
    try {
      return await _channel.invokeMethod<String>('addEvent', {
        'title': title,
        'notes': notes,
        'startAtMillis': startAt.millisecondsSinceEpoch,
        'endAtMillis': endAt.millisecondsSinceEpoch,
        'startDate': _dateOnly(startAt),
        'endDate': _dateOnly(endAt),
        'allDay': allDay,
      });
    } on PlatformException catch (error) {
      throw AppException(error.message ?? '캘린더에 일정을 추가하지 못했습니다.');
    } on MissingPluginException {
      throw const AppException('이 기기에서 캘린더 연동을 사용할 수 없습니다.');
    }
  }

  Future<void> openCalendar({DateTime? date}) async {
    try {
      await _channel.invokeMethod<bool>('openCalendar', {
        if (date != null) 'dateMillis': date.millisecondsSinceEpoch,
        if (date != null) 'date': _dateOnly(date),
      });
    } on PlatformException catch (error) {
      throw AppException(error.message ?? '캘린더 앱을 열지 못했습니다.');
    } on MissingPluginException {
      throw const AppException('이 기기에서 캘린더 앱 열기를 사용할 수 없습니다.');
    }
  }

  String _dateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
