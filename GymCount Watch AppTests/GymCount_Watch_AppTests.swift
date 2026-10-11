import Foundation
import Testing
import HealthKit
@testable import GymCount_Watch_App

@MainActor
@Suite(.serialized)
struct GymCount_Watch_AppTests {
    @Test func decidedDenialShowsHelpInsteadOfPromisingAnotherSheet() async {
        var requests = 0
        let link = WatchCaptureLink(activateConnectivity: false, authorization: CaptureHealthAuthorization(
            available: { true }, status: { .sharingDenied }, requestStatus: { .unnecessary },
            request: { requests += 1 }))
        #expect(await link.authorizeCapture() == false)
        #expect(requests == 0)
        #expect(link.needsAuthorization)
        #expect(link.showingAuthorizationHelp)
        #expect(link.authorizationMessage == "手表尚未获得体能训练权限")
        #expect(!link.authorizing)
    }

    @Test func permissionChangeClearsOldFailureWithoutOverwritingUploadFeedback() async {
        var permission = HKAuthorizationStatus.sharingDenied
        let link = WatchCaptureLink(activateConnectivity: false, authorization: CaptureHealthAuthorization(
            available: { true }, status: { permission }, requestStatus: { .unnecessary }, request: {}))
        _ = await link.authorizeCapture()
        link.message = "上传完成"
        defer { CollectionStore.shared.message = "" }
        permission = .sharingAuthorized
        link.refreshAuthorization()
        #expect(!link.needsAuthorization)
        #expect(!link.showingAuthorizationHelp)
        #expect(link.authorizationMessage.isEmpty)
        #expect(CollectionStore.shared.message == "上传完成")
        #expect(await link.authorizeCapture())
    }

    @Test func firstPermissionRequestChecksActualGrantAndPrepareIsReady() async {
        var permission = HKAuthorizationStatus.notDetermined
        var requests = 0
        let link = WatchCaptureLink(activateConnectivity: false, authorization: CaptureHealthAuthorization(
            available: { true }, status: { permission }, requestStatus: { .shouldRequest },
            request: { requests += 1; permission = .sharingAuthorized }))
        #expect(await link.authorizeCapture())
        #expect(requests == 1)
        #expect(!link.needsAuthorization)
        #expect(!link.authorizing)
        var response: [String: Any] = [:]
        await link.handle(["command": "prepare", "exercise": "bicep_curl"]) { response = $0 }
        #expect(response["ready"] as? Bool == true)
        CollectionStore.shared.message = ""
    }

    @Test func authorizationRequestFailureProducesVisibleResult() async {
        let link = WatchCaptureLink(activateConnectivity: false, authorization: CaptureHealthAuthorization(
            available: { true }, status: { .notDetermined }, requestStatus: { .shouldRequest },
            request: { throw NSError(domain: "HealthKit", code: 5) }))
        #expect(await link.authorizeCapture() == false)
        #expect(link.showingAuthorizationHelp)
        #expect(link.authorizationMessage.contains("5"))
        #expect(!link.authorizing)
    }

    @Test func successfulRequestCompletionDoesNotImplyPermissionGranted() async {
        var permission = HKAuthorizationStatus.notDetermined
        let link = WatchCaptureLink(activateConnectivity: false, authorization: CaptureHealthAuthorization(
            available: { true }, status: { permission }, requestStatus: { .shouldRequest },
            request: { permission = .sharingDenied }))
        #expect(await link.authorizeCapture() == false)
        #expect(link.needsAuthorization)
        #expect(link.showingAuthorizationHelp)
    }
    @Test func phonePreparationOpensMatchingPageBeforeStartingSensors() async {
        let link = WatchCaptureLink(activateConnectivity: false)
        var response: [String: Any] = [:]
        await link.handle(["command": "prepare", "exercise": "bicep_curl"]) { response = $0 }
        #expect(link.showingCapture)
        #expect(link.requestedExercise == "bicep_curl")
        #expect(!link.remoteSession)
        #expect(!CollectionStore.shared.recording)
        #expect(response["ready"] != nil || response["error"] != nil || response["authorizationPending"] as? Bool == true)
    }

    @Test func phonePreparationPreservesUnconfirmedCapture() async {
        let store = CollectionStore.shared
        let existing = record()
        store.draft = existing
        defer { store.draft = nil }
        let link = WatchCaptureLink(activateConnectivity: false)
        var response: [String: Any] = [:]
        await link.handle(["command": "prepare", "exercise": "bicep_curl"]) { response = $0 }
        #expect(response["error"] != nil)
        #expect(store.draft?.session_id == existing.session_id)
        #expect(store.draft?.exercise == "squat")
        #expect(!link.showingCapture)
    }

    @Test func standaloneCaptureRequiresWorkoutAuthorizationBeforeSensors() async {
        let link = WatchCaptureLink(activateConnectivity: false, authorization: CaptureHealthAuthorization(
            available: { true }, status: { .sharingDenied }, requestStatus: { .unnecessary }, request: {}))
        await link.startStandaloneCapture(exercise: "bench_press", notes: "")
        #expect(!CollectionStore.shared.recording)
        #expect(!link.startingCapture)
        #expect(!link.isCaptureWorkoutRunning)
        #expect(link.showingAuthorizationHelp)
        #expect(link.message == "请先允许体能训练权限")
        CollectionStore.shared.message = ""
    }

    private func record() -> CaptureRecord {
        CaptureRecord(session_id: UUID(), started_at: Date(), exercise: "squat", actual_count: 0,
            detected_count: 0, duration_seconds: 0.025, wrist: "left", watch_crown: "right", pace: "normal",
            watch_model: "test", os_version: "test", app_version: "test", algorithm_version: "test",
            participant_id: UUID(), notes: "", samples: [CaptureSample(t: 0, received_t: 0, x: 0, y: 0, z: 1),
                CaptureSample(t: 0.025, received_t: 0.025, x: 0, y: 0, z: 1)],
            gyroscope_samples: [], motion_samples: [], magnetometer_samples: [],
            sensor_availability: CaptureAvailability(gyroscope: false, device_motion: false, magnetometer: false),
            detected_events: [], reference_events_truncated: false)
    }

    @Test func failedUploadRetainsEditableCountAndSuccessfulRetryRemovesQueue() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var status = 500
        var sentCounts: [Int] = []
        let store = CollectionStore(folder: folder) { request in
            let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            sentCounts.append(json["actual_count"] as! Int)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        store.draft = record()
        #expect(sentCounts.isEmpty)
        await store.persist(10)
        #expect(store.draft?.actual_count == 10)
        #expect(store.pending == 1)
        #expect(store.message.contains("上传失败（500）"))
        #expect(!store.message.contains("上传完成"))
        status = 201
        await store.persist(12)
        #expect(sentCounts == [10, 12])
        #expect(store.draft == nil)
        #expect(store.pending == 0)
        #expect(store.message == "上传完成")
    }

    @Test func networkFailurePreservesQueueUntilExplicitDiscard() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CollectionStore(folder: folder) { _ in throw URLError(.timedOut) }
        store.draft = record()
        await store.persist(8)
        #expect(store.draft?.actual_count == 8)
        #expect(store.pending == 1)
        #expect(store.message.contains("记录已保留"))
        store.discard()
        #expect(store.draft == nil)
        #expect(store.pending == 0)
    }
}
