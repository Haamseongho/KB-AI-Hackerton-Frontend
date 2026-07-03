package com.kbds.aihackathon.voicedoc

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val calendarChannel = "com.kbds.aihackathon.voicedoc/calendar"
    private val calendarPermissionRequest = 4010
    private var pendingCalendarEvent: CalendarEventArgs? = null
    private var pendingCalendarResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            calendarChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "addEvent" -> {
                    val args = CalendarEventArgs(
                        title = call.argument<String>("title")?.trim().orEmpty(),
                        notes = call.argument<String>("notes"),
                        startAtMillis = call.argument<Long>("startAtMillis"),
                        endAtMillis = call.argument<Long>("endAtMillis"),
                        startDate = call.argument<String>("startDate"),
                        endDate = call.argument<String>("endDate"),
                        allDay = call.argument<Boolean>("allDay") ?: true
                    )

                    if (args.title.isEmpty() || args.startAtMillis == null || args.endAtMillis == null) {
                        result.error("INVALID_ARGUMENT", "일정 제목과 날짜를 확인해 주세요.", null)
                        return@setMethodCallHandler
                    }

                    addCalendarEvent(args, result)
                }
                "openCalendar" -> {
                    openCalendar(
                        date = call.argument<String>("date"),
                        dateMillis = call.argument<Long>("dateMillis"),
                        result = result
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != calendarPermissionRequest) return

        val result = pendingCalendarResult ?: return
        val args = pendingCalendarEvent
        pendingCalendarResult = null
        pendingCalendarEvent = null

        if (args == null || grantResults.any { it != PackageManager.PERMISSION_GRANTED }) {
            result.error("CALENDAR_PERMISSION_DENIED", "캘린더 접근 권한이 필요합니다.", null)
            return
        }
        insertCalendarEvent(args, result)
    }

    private fun addCalendarEvent(args: CalendarEventArgs, result: MethodChannel.Result) {
        val hasReadPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED
        val hasWritePermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.WRITE_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED

        if (hasReadPermission && hasWritePermission) {
            insertCalendarEvent(args, result)
            return
        }

        pendingCalendarEvent = args
        pendingCalendarResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
            calendarPermissionRequest
        )
    }

    private fun insertCalendarEvent(args: CalendarEventArgs, result: MethodChannel.Result) {
        val calendarId = findWritableCalendarId()
        if (calendarId == null) {
            result.error("CALENDAR_UNAVAILABLE", "사용 가능한 캘린더를 찾을 수 없습니다.", null)
            return
        }

        val eventStartAt = eventStartAt(args)
        val eventEndAt = eventEndAt(args)
        val eventTimeZone = if (args.allDay) "UTC" else TimeZone.getDefault().id

        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, args.title)
            put(CalendarContract.Events.DESCRIPTION, args.notes)
            put(CalendarContract.Events.DTSTART, eventStartAt)
            put(CalendarContract.Events.DTEND, eventEndAt)
            put(CalendarContract.Events.ALL_DAY, if (args.allDay) 1 else 0)
            put(CalendarContract.Events.EVENT_TIMEZONE, eventTimeZone)
        }

        try {
            val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            val eventId = uri?.lastPathSegment
            if (eventId == null) {
                result.error("CALENDAR_SAVE_FAILED", "캘린더에 일정을 저장하지 못했습니다.", null)
                return
            }
            result.success(eventId)
        } catch (error: SecurityException) {
            result.error("CALENDAR_PERMISSION_DENIED", "캘린더 접근 권한이 필요합니다.", null)
        } catch (error: IllegalArgumentException) {
            result.error("CALENDAR_SAVE_FAILED", "캘린더에 일정을 저장하지 못했습니다.", null)
        }
    }

    private fun eventStartAt(args: CalendarEventArgs): Long {
        if (args.allDay) {
            dateToUtcMillis(args.startDate)?.let { return it }
        }
        return args.startAtMillis ?: 0L
    }

    private fun eventEndAt(args: CalendarEventArgs): Long {
        if (args.allDay) {
            dateToUtcMillis(args.endDate)?.let { return it }
        }
        return args.endAtMillis ?: eventStartAt(args)
    }

    private fun dateToUtcMillis(value: String?): Long? {
        if (value == null) return null
        val parts = value.split("-")
        if (parts.size != 3) return null
        val year = parts[0].toIntOrNull() ?: return null
        val month = parts[1].toIntOrNull() ?: return null
        val day = parts[2].toIntOrNull() ?: return null
        return Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month - 1)
            set(Calendar.DAY_OF_MONTH, day)
        }.timeInMillis
    }

    private fun openCalendar(date: String?, dateMillis: Long?, result: MethodChannel.Result) {
        val targetMillis = dateToUtcMillis(date) ?: dateMillis ?: System.currentTimeMillis()
        val uri = Uri.parse("${CalendarContract.CONTENT_URI}/time/$targetMillis")
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("CALENDAR_OPEN_FAILED", "캘린더 앱을 열지 못했습니다.", null)
        }
    }

    private fun findWritableCalendarId(): Long? {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.VISIBLE
        )
        val selection =
            "${CalendarContract.Calendars.VISIBLE} = 1 AND " +
                "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ?"
        val args = arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString())
        val cursor = contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            selection,
            args,
            null
        ) ?: return null

        cursor.use {
            var fallbackId: Long? = null
            val idIndex = it.getColumnIndexOrThrow(CalendarContract.Calendars._ID)
            val primaryIndex = it.getColumnIndexOrThrow(CalendarContract.Calendars.IS_PRIMARY)
            while (it.moveToNext()) {
                val id = it.getLong(idIndex)
                if (fallbackId == null) fallbackId = id
                if (it.getInt(primaryIndex) == 1) return id
            }
            return fallbackId
        }
    }

    private data class CalendarEventArgs(
        val title: String,
        val notes: String?,
        val startAtMillis: Long?,
        val endAtMillis: Long?,
        val startDate: String?,
        val endDate: String?,
        val allDay: Boolean
    )
}
