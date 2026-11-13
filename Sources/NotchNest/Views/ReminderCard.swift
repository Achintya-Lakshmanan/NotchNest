import SwiftUI

struct ReminderCard: View {
    @ObservedObject var service: ReminderService
    var liveRefresh = true
    /// One-line strip (under the month grid) instead of the tall card.
    var compact = false
    private let lilac = Color(red: 0.72, green: 0.65, blue: 1)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Group {
                if compact {
                    compactRow(now: context.date)
                } else if case let .ready(reminder) = service.state {
                    reminderButton(reminder, now: context.date)
                } else {
                    placeholder
                }
            }
            .padding(.horizontal, compact ? 9 : 10)
            .padding(.vertical, compact ? 6 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lilac.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { if liveRefresh { service.start() } }
        .onDisappear { if liveRefresh { service.stop() } }
        .task {
            guard liveRefresh else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                service.refresh()
            }
        }
    }

    private func heading(_ text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "bell.badge.fill").font(.system(size: 8))
            Text(text).font(.system(size: 8, weight: .bold)).tracking(0.6)
        }
        .foregroundStyle(tint ?? lilac)
        .lineLimit(1)
    }

    private func reminderButton(_ reminder: ReminderInfo, now: Date) -> some View {
        let overdue = reminder.isOverdue(at: now)
        let components = reminder.colorComponents
        let listColor = components.count >= 3
            ? Color(red: components[0], green: components[1], blue: components[2]) : lilac
        return Button { service.openReminders() } label: {
            VStack(alignment: .leading, spacing: 5) {
                heading(overdue ? "OVERDUE REMINDER" : "NEXT REMINDER", tint: overdue ? .orange : nil)
                Text(reminder.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    if overdue { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 8)) }
                    Text(reminder.dueLabel(at: now))
                        .font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                }
                .foregroundStyle(overdue ? .orange : lilac.opacity(0.95))
                HStack(spacing: 4) {
                    Circle().fill(listColor).frame(width: 4, height: 4)
                    Text(reminder.listName).font(.system(size: 8)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(reminder.title)\n\(reminder.due.formatted(date: .complete, time: reminder.dateOnly ? .omitted : .shortened))\nOpen Apple Reminders")
        .accessibilityElement(children: .combine)
    }

    private func compactRow(now: Date) -> some View {
        HStack(spacing: 6) {
            switch service.state {
            case let .ready(reminder):
                let overdue = reminder.isOverdue(at: now)
                Button { service.openReminders() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: overdue ? "exclamationmark.circle.fill" : "bell.badge.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(overdue ? .orange : lilac)
                        Text(reminder.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(reminder.dueLabel(at: now))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(overdue ? .orange : lilac.opacity(0.95))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(reminder.title) · \(reminder.listName)\n\(reminder.due.formatted(date: .complete, time: reminder.dateOnly ? .omitted : .shortened))\nOpen Apple Reminders")
                .accessibilityElement(children: .combine)
            case .connect:
                compactLabel("Your next to-do, here.")
                Button(service.requestingAccess ? "Connecting…" : "Connect") { service.requestAccess() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(lilac)
                    .disabled(service.requestingAccess || !liveRefresh)
            case .denied:
                compactLabel("Reminders access is off.")
                Button("Open Settings") { service.openSettings() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(lilac)
            case .loading:
                compactLabel("Checking reminders…")
            case .empty:
                compactLabel("No dated reminders")
            case .failed:
                compactLabel("Couldn't load reminders.")
                Button("Retry") { service.refresh() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(lilac)
            }
        }
        .frame(height: 15)
    }

    private func compactLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.badge.fill").font(.system(size: 9)).foregroundStyle(lilac)
            Text(text).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            Spacer(minLength: 4)
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("NEXT REMINDER")
            switch service.state {
            case .connect:
                Text("Your next to-do, here.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                Button(service.requestingAccess ? "Connecting…" : "Connect Reminders") { service.requestAccess() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(lilac)
                    .disabled(service.requestingAccess || !liveRefresh)
            case .denied:
                Text("Allow Reminders in Privacy & Security.")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") { service.openSettings() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(lilac)
            case .loading:
                Text("Checking reminders…").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            case .empty:
                Text("No dated reminders")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                Text("Set a due date to show it here.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
            case .failed:
                Text("Couldn't load reminders.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                Button("Try again") { service.refresh() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(lilac)
            case .ready: EmptyView()
            }
        }
    }
}
