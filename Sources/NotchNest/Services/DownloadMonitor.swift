import AppKit
import Foundation
import Darwin

/// Watches `~/Downloads` for in-progress Chrome/browser temp files and reports
/// presence only (no % / size / ETA — those aren't reliably available).
final class DownloadMonitor: NSObject {
    typealias UpdateHandler = ([DownloadItem]) -> Void
    typealias FinishedHandler = (String) -> Void

    private var onUpdate: UpdateHandler?
    private var onFinished: FinishedHandler?
    private var pollTimer: Timer?
    private var source: DispatchSourceFileSystemObject?
    private var dirFD: CInt = -1
    private var finishedObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "com.notchnest.downloads", qos: .utility)

    private var lastPublished: [DownloadItem] = []

    private static let tempSuffixes = [".crdownload", ".download", ".part", ".partial", ".opdownload"]

    func start(
        onUpdate: @escaping UpdateHandler,
        onFinished: @escaping FinishedHandler
    ) {
        self.onUpdate = onUpdate
        self.onFinished = onFinished
        watchDownloadsDirectory()
        observeFinishedNotification()
        scanAndPublish()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.scanAndPublish()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        source?.cancel()
        source = nil
        if dirFD >= 0 { close(dirFD); dirFD = -1 }
        if let finishedObserver {
            DistributedNotificationCenter.default().removeObserver(finishedObserver)
            self.finishedObserver = nil
        }
    }

    deinit { stop() }

    // MARK: - Scan

    private func scanAndPublish() {
        queue.async { [weak self] in
            guard let self else { return }
            let items = self.scanTempDownloads()
            DispatchQueue.main.async {
                if items != self.lastPublished {
                    self.lastPublished = items
                    self.onUpdate?(items)
                }
            }
        }
    }

    private func downloadsURL() -> URL? {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return url
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
    }

    private func scanTempDownloads() -> [DownloadItem] {
        guard let dir = downloadsURL() else { return [] }
        _ = FileManager.default.isReadableFile(atPath: dir.path)
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var items: [DownloadItem] = []
        for url in contents {
            let name = url.lastPathComponent
            let lower = name.lowercased()
            guard Self.tempSuffixes.contains(where: { lower.hasSuffix($0) }) else { continue }
            items.append(DownloadItem(path: url.path, name: name))
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - FS watch

    private func watchDownloadsDirectory() {
        guard let dir = downloadsURL() else { return }
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        dirFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .link],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.scanAndPublish() }
        src.setCancelHandler { [weak self] in
            if let self, self.dirFD >= 0 {
                close(self.dirFD)
                self.dirFD = -1
            }
        }
        source = src
        src.resume()
    }

    private func observeFinishedNotification() {
        finishedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.DownloadFileFinished"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let path = (note.object as? String)
                ?? (note.userInfo?["path"] as? String)
                ?? ""
            let name = path.isEmpty
                ? "Download"
                : URL(fileURLWithPath: path).lastPathComponent
            self?.onFinished?(name)
            self?.scanAndPublish()
        }
    }
}
