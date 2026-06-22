import EventKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let calendarChannel = "com.kbds.aihackathon.voicedoc/calendar"
  private let eventStore = EKEventStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "VoiceDocCalendarChannel") {
      let channel = FlutterMethodChannel(
        name: calendarChannel,
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "addEvent" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.addCalendarEvent(call: call, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func addCalendarEvent(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let title = args["title"] as? String,
      let startAtMillis = numberValue(args["startAtMillis"]),
      let endAtMillis = numberValue(args["endAtMillis"]),
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      result(FlutterError(
        code: "INVALID_ARGUMENT",
        message: "일정 제목과 날짜를 확인해 주세요.",
        details: nil
      ))
      return
    }

    requestCalendarAccess { [weak self] granted in
      guard granted, let self = self else {
        result(FlutterError(
          code: "CALENDAR_PERMISSION_DENIED",
          message: "캘린더 접근 권한이 필요합니다.",
          details: nil
        ))
        return
      }

      let event = EKEvent(eventStore: self.eventStore)
      event.title = title
      event.notes = args["notes"] as? String
      event.startDate = Date(timeIntervalSince1970: startAtMillis.doubleValue / 1000)
      event.endDate = Date(timeIntervalSince1970: endAtMillis.doubleValue / 1000)
      event.isAllDay = args["allDay"] as? Bool ?? true
      event.calendar = self.eventStore.defaultCalendarForNewEvents

      do {
        try self.eventStore.save(event, span: .thisEvent)
        result(event.eventIdentifier)
      } catch {
        result(FlutterError(
          code: "CALENDAR_SAVE_FAILED",
          message: "캘린더에 일정을 저장하지 못했습니다.",
          details: error.localizedDescription
        ))
      }
    }
  }

  private func requestCalendarAccess(completion: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *) {
      let status = EKEventStore.authorizationStatus(for: .event)
      if status == .fullAccess || status == .writeOnly {
        completion(true)
        return
      }
      eventStore.requestFullAccessToEvents { granted, _ in
        DispatchQueue.main.async {
          completion(granted)
        }
      }
      return
    }

    eventStore.requestAccess(to: .event) { granted, _ in
      DispatchQueue.main.async {
        completion(granted)
      }
    }
  }

  private func numberValue(_ value: Any?) -> NSNumber? {
    if let number = value as? NSNumber {
      return number
    }
    if let int = value as? Int {
      return NSNumber(value: int)
    }
    if let double = value as? Double {
      return NSNumber(value: double)
    }
    return nil
  }
}
