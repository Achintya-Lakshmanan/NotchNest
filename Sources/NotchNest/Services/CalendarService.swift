import EventKit
import AppKit

final class CalendarService: @unchecked Sendable {
    private let store = EKEventStore()

    var isAuthorized: Bool {
        if #available(macOS 14.0, *) {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        } else {
            return EKEventStore.authorizationStatus(for: .event) == .authorized
        }
    }

    func requestAccess(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func todayEvents(hiding hidden: Set<String> = []) -> [CalEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events(from: start, to: end, hiding: hidden)
    }

    struct CalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let source: String
        let colorComponents: [CGFloat]
    }

    /// Event calendars, grouped by account, for the Preferences picker.
    func calendars() -> [CalendarInfo] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event).map { calendar in
            let color = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.sRGB)
            return CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                                source: calendar.source?.title ?? "",
                                colorComponents: color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent, 1] } ?? [])
        }
        .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    func events(from start: Date, to end: Date, hiding hidden: Set<String> = []) -> [CalEvent] {
        guard isAuthorized else { return [] }
        let calendars = hidden.isEmpty ? nil
            : store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        if calendars?.isEmpty == true { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { ev in
                // Skip invitations you declined.
                ev.attendees?.first(where: { $0.isCurrentUser })?.participantStatus != .declined
            }
            .sorted { ($0.startDate ?? start) < ($1.startDate ?? start) }
            .map { ev in
                let color = NSColor(cgColor: ev.calendar?.cgColor ?? NSColor.systemBlue.cgColor)?
                    .usingColorSpace(.sRGB)
                let comps: [CGFloat] = color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent] }
                    ?? [0.2, 0.5, 1, 1]
                return CalEvent(
                    id: Self.occurrenceID(base: ev.eventIdentifier ?? ev.calendarItemIdentifier,
                                          start: ev.startDate ?? start),
                    title: ev.title ?? "Untitled",
                    start: ev.startDate ?? start,
                    end: ev.endDate ?? start,
                    isAllDay: ev.isAllDay,
                    colorComponents: comps,
                    videoURL: Self.meetingURL(from: ev),
                    location: Self.place(from: ev.location),
                    isFree: ev.availability == .free
                )
            }
    }

    /// The event location without meeting links, e.g. "Willard Building 062".
    /// Recurring events share one eventIdentifier; adding the start makes each
    /// occurrence (Mon/Wed/Fri lecture) distinct but stable across refreshes.
    static func occurrenceID(base: String, start: Date) -> String {
        "\(base)@\(Int(start.timeIntervalSince1970))"
    }

    static func place(from location: String?) -> String? {
        guard let location else { return nil }
        let cleaned = location
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
        return cleaned.isEmpty ? nil : cleaned
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
