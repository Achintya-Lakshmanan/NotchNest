import AppKit
import SwiftUI
import XCTest
@testable import NotchNest

final class ArtworkTintTests: XCTestCase {
    private func track(playing: Bool, title: String = "Track", elapsed: Double = 60) -> NowPlaying {
        NowPlaying(app: .music, title: title, artist: "Artist", album: "Album", isPlaying: playing,
                   elapsed: elapsed, duration: 240, artworkURL: nil)
    }

    @MainActor
    private func makeState(delay: Duration = .milliseconds(100)) -> NotchState {
        let state = NotchState(metrics: NotchMetrics(notchWidth: 200, notchHeight: 32, screenFrame: .zero),
                               musicIdleDelay: delay)
        state.disableLiveRefresh = true
        state.artwork = NSImage(size: CGSize(width: 8, height: 8))
        state.artworkColor = .purple
        return state
    }

    @MainActor
    func testAlreadyPausedAtLaunchIsBlackAndRetainsArtwork() {
        let state = makeState()
        state.nowPlaying = track(playing: false)
        XCTAssertFalse(state.musicPresentationActive)
        XCTAssertNil(state.displayedNowPlaying, "An old paused track must not appear on launch")
        XCTAssertNotNil(state.artwork)
        XCTAssertEqual(state.artworkColor, .purple)
    }

    @MainActor
    func testPlayingKeepsTintBeyondPauseDelay() async throws {
        let state = makeState()
        state.nowPlaying = track(playing: true)
        XCTAssertTrue(state.musicPresentationActive)
        XCTAssertEqual(state.displayedNowPlaying, state.nowPlaying)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(state.musicPresentationActive)
    }

    @MainActor
    func testPauseExpiresInExpandedAndCompactWithoutDeletingArtwork() async throws {
        let state = makeState()
        state.nowPlaying = track(playing: true)
        state.nowPlaying = track(playing: false)
        XCTAssertTrue(state.musicPresentationActive, "A short pause should keep the tint")
        XCTAssertEqual(state.displayedNowPlaying, state.nowPlaying, "Keep controls for a brief pause")
        state.isExpanded = true
        state.tab = .calendar
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(state.musicPresentationActive)
        XCTAssertNil(state.displayedNowPlaying)
        state.isExpanded = false
        XCTAssertFalse(state.musicPresentationActive)
        XCTAssertNil(state.displayedNowPlaying)
        XCTAssertNotNil(state.artwork)
        XCTAssertEqual(state.artworkColor, .purple)
    }

    @MainActor
    func testPausedMetadataUpdatesDoNotRestartTheCountdown() async throws {
        let state = makeState(delay: .milliseconds(60))
        state.nowPlaying = track(playing: true)
        state.nowPlaying = track(playing: false)
        for index in 0..<8 {
            try await Task.sleep(for: .milliseconds(20))
            state.nowPlaying = track(playing: false, title: "Paused \(index)", elapsed: Double(index))
        }
        XCTAssertFalse(state.musicPresentationActive)
        XCTAssertNil(state.displayedNowPlaying, "Repeated paused metadata must not revive the overview")
    }

    @MainActor
    func testResumeCancelsPendingFadeAndRestoresExpiredTint() async throws {
        let state = makeState()
        state.nowPlaying = track(playing: true)
        state.nowPlaying = track(playing: false)
        state.nowPlaying = track(playing: true)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(state.musicPresentationActive, "An old pause must not hide playing music")
        state.nowPlaying = track(playing: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(state.musicPresentationActive)
        state.nowPlaying = track(playing: true)
        XCTAssertTrue(state.musicPresentationActive)
        XCTAssertEqual(state.displayedNowPlaying, state.nowPlaying)
    }

    @MainActor
    func testMusicClosingClearsTintAndCancelsOldPause() async throws {
        let state = makeState()
        state.nowPlaying = track(playing: true)
        state.nowPlaying = track(playing: false)
        state.nowPlaying = nil
        XCTAssertFalse(state.musicPresentationActive)
        state.nowPlaying = track(playing: true, title: "New song")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(state.musicPresentationActive)
    }

    @MainActor
    func testRenderedExpandedBackgroundReturnsToBlack() async throws {
        let state = makeState()
        state.isExpanded = true
        state.nowPlaying = track(playing: true)
        func brightness(topStrip: Bool = false) throws -> CGFloat {
            let renderer = ImageRenderer(content: NotchRootView(state: state).environmentObject(state)
                .frame(width: state.metrics.expandedSize.width, height: state.metrics.expandedSize.height))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let y = topStrip ? 5 : Int(state.metrics.notchHeight) + 5
            let color = try XCTUnwrap(bitmap.colorAt(x: 270, y: y)?.usingColorSpace(.sRGB))
            return color.redComponent + color.greenComponent + color.blueComponent
        }
        XCTAssertLessThan(try brightness(topStrip: true), 0.01, "The strip behind the cutout stays black during playback")
        XCTAssertGreaterThan(try brightness(), 0.1)
        state.nowPlaying = track(playing: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertLessThan(try brightness(), 0.01)
        state.nowPlaying = track(playing: true)
        XCTAssertLessThan(try brightness(topStrip: true), 0.01)
        XCTAssertGreaterThan(try brightness(), 0.1)
    }

    @MainActor
    func testMusicPaneRendersIdleInsteadOfAnOldTrack() async throws {
        let state = makeState()
        func render() throws -> Data {
            let renderer = ImageRenderer(content: MusicPane().environmentObject(state)
                .frame(width: 496, height: 200))
            renderer.scale = 1
            return try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        }
        let idle = try render()
        state.nowPlaying = track(playing: false, title: "Old paused track")
        XCTAssertEqual(try render(), idle, "A stale track should render the normal empty state")
        state.nowPlaying = track(playing: true)
        XCTAssertNotEqual(try render(), idle)
        state.nowPlaying = track(playing: false)
        XCTAssertNotEqual(try render(), idle, "Brief pauses retain the controls")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(try render(), idle, "After timeout the old overview must be gone")
        state.nowPlaying = track(playing: true)
        XCTAssertNotEqual(try render(), idle, "Resuming restores the overview")
    }
}
