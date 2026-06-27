import EventKit
import AppKit

final class CalendarService {
    private let store = EKEventStore()

    var isAuthorized: Bool {
        if #available(macOS 14.0, *) {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        } else {
            return EKEventStore.authorizationStatus(for: .event) == .authorized
        }
    }

    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func todayEvents() -> [CalEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events(from: start, to: end)
    }

    func events(from start: Date, to end: Date) -> [CalEvent] {
        guard isAuthorized else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { ($0.startDate ?? start) < ($1.startDate ?? start) }
            .map { ev in
                let color = NSColor(cgColor: ev.calendar?.cgColor ?? NSColor.systemBlue.cgColor)?
                    .usingColorSpace(.sRGB)
                let comps: [CGFloat] = color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent] }
                    ?? [0.2, 0.5, 1, 1]
                return CalEvent(
                    id: ev.eventIdentifier ?? UUID().uuidString,
                    title: ev.title ?? "Untitled",
                    start: ev.startDate ?? start,
                    end: ev.endDate ?? start,
                    isAllDay: ev.isAllDay,
                    colorComponents: comps,
                    videoURL: Self.meetingURL(from: ev)
                )
            }
    }

    /// Finds a video-call link in the event's url / location / notes.
    private static func meetingURL(from ev: EKEvent) -> URL? {
        let haystack = [ev.url?.absoluteString, ev.location, ev.notes]
            .compactMap { $0 }
            .joined(separator: " ")
        let pattern = #"https?://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com|whereby\.com|around\.co)[^\s<>"]*"#
        if let range = haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let trimmed = haystack[range].trimmingCharacters(in: CharacterSet(charactersIn: ".,);]"))
            return URL(string: trimmed)
        }
        // Fall back to the event's own URL if it's http(s).
        if let url = ev.url, url.scheme?.hasPrefix("http") == true { return url }
        return nil
    }
}
