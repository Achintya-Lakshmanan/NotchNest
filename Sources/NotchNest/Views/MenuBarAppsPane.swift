import SwiftUI

struct MenuBarAppsPane: View {
    @ObservedObject var service: MenuBarAppsService
    let liveRefresh: Bool
    @State private var section = MenuBarSection.apps

    private var visibleItems: [MenuBarAppItem] { service.items.filter { $0.section == section } }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu bar apps").font(.system(size: 14, weight: .semibold))
                    Text("Your menus, without crowding the menu bar.")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 4)
                if service.shortcutAvailable {
                    Text("⌃⌥M").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 7).frame(height: 23)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                        .help("Shortcut to open this drawer")
                }
                Button { service.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                        .frame(width: 25, height: 23)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain).help("Refresh menu bar apps")
                .accessibilityLabel("Refresh menu bar apps")
                .disabled(service.isLoading || !liveRefresh)
            }
            if !service.hasAccess {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield").font(.system(size: 24)).foregroundStyle(.blue)
                    Text("Allow Accessibility to read and open menu bar items.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                    Button("Allow Accessibility") { service.requestAccess() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    ForEach(MenuBarSection.allCases, id: \.self) { value in
                        Button { section = value } label: {
                            Text(value.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(.white.opacity(section == value ? 0.16 : 0.05), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(value.rawValue) menus")
                    }
                    Spacer()
                }
                if visibleItems.isEmpty {
                    VStack(spacing: 8) {
                        if service.isLoading { ProgressView().controlSize(.small) }
                        Text(service.isLoading ? "Finding menus..." : "No \(section.rawValue.lowercased()) menus found. Try Refresh.")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(visibleItems) { item in
                                MenuBarAppButton(item: item) { service.select(item) }
                            }
                        }.padding(.vertical, 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { if liveRefresh { service.refresh() } }
    }
}

private struct MenuBarAppButton: View {
    let item: MenuBarAppItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if let icon = item.icon { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "menubar.rectangle").resizable().scaledToFit() }
                }.frame(width: 26, height: 26)
                Text(item.label).font(.system(size: 9, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(.white.opacity(hovering ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .topTrailing) {
                if item.visibility == .covered || item.visibility == .offscreen {
                    Image(systemName: "eye.slash.fill").font(.system(size: 8)).foregroundStyle(.orange)
                        .padding(5)
                        .accessibilityLabel("Hidden in the menu bar")
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(item.label) menu" + (item.visibility == .covered ? "\nHidden behind the notch"
              : item.visibility == .offscreen ? "\nHidden: the menu bar is full" : ""))
        .accessibilityLabel("Open \(item.label) menu")
    }
}
