import Foundation
import CryptoKit

struct CaptureClockReading {
    let phoneSent: Double
    let watchReceived: Double
    let watchSent: Double
    let phoneReceived: Double
    var roundTrip: Double { max(0, phoneReceived - phoneSent - (watchSent - watchReceived)) }
    var offset: Double { ((watchReceived - phoneSent) + (watchSent - phoneReceived)) / 2 }
}

struct VideoCaptureManifest: Codable, Identifiable {
    let id: UUID
    let exercise: String
    let createdAt: Date
    var videoStartedAt: Double?
    var videoDuration: Double?
    var watchClockOffset: Double = 0 // watch wall clock minus phone wall clock
    var clockRoundTrip: Double = 0
    var sampleOriginOnPhone: Double?
    var detectedCount: Int = 0
    var actualCount: Int?
    var videoComplete = false
    var sensorComplete = false
    var error: String?
    // Movie start is estimated from the recording callback minus recordedDuration.
    // RTT bounds network uncertainty only; it does not guarantee frame-accurate alignment.
    var videoAnchorMethod: String = "recording_callback_minus_recorded_duration"
    var referenceEvents: [Double] = []
    var alignmentCorrection: Double = 0
    var cloudRecordID: Int?
    var cloudVideoUploadedAt: Date?
    var cloudUploadComplete: Bool { cloudRecordID != nil && cloudVideoUploadedAt != nil }
    var uploadStatusTitle: String {
        cloudUploadComplete ? "已上传" : cloudRecordID != nil ? "仅采样已上传" : "未上传"
    }
    var sensorOffsetInVideo: Double? {
        guard let origin = sampleOriginOnPhone, let video = videoStartedAt else { return nil }
        return origin - video + alignmentCorrection
    }
}

enum CaptureCloudUpload {
    struct SensorReply: Decodable {
        let id: Int
        let session_id: UUID
        let video_upload_token: String
    }
    struct VideoTicket: Decodable {
        let upload_url: URL
        let headers: [String: String]
        let receipt: String
    }
    struct Completion: Decodable {
        let id: Int
        let session_id: UUID
        let video_complete: Bool
    }
    struct UploadError: LocalizedError {
        let text: String
        var errorDescription: String? { text }
    }
    static let base = URL(string: "https://api.flyingrtx.com/api/v1/gymcount/")!

    static func checkedJSON(_ data: Data, response: URLResponse, expected: Int, fallback: String) throws -> Data {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == expected else {
            let detail = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["detail"] as? String
            throw UploadError(text: detail ?? "\(fallback)（\(status)）")
        }
        return data
    }
    static func post(_ path: String, body: Data? = nil, token: String? = nil) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        return try checkedJSON(data, response: response, expected: path == "sessions" ? 201 : 200, fallback: "上传失败")
    }
    static func descriptor(file: URL, manifest: VideoCaptureManifest) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var md5 = Insecure.MD5(), size = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            size += chunk.count; md5.update(data: chunk)
        }
        guard size > 0, size <= 512 * 1024 * 1024, let duration = manifest.videoDuration, duration > 0 else {
            throw UploadError(text: "录像文件不完整或超过 512 MB")
        }
        var body: [String: Any] = ["size": size, "md5": Data(md5.finalize()).base64EncodedString(),
            "duration_seconds": duration, "clock_round_trip_seconds": manifest.clockRoundTrip,
            "alignment_correction_seconds": manifest.alignmentCorrection, "reference_events": manifest.referenceEvents]
        if let offset = manifest.sensorOffsetInVideo { body["sensor_offset_seconds"] = offset }
        return try JSONSerialization.data(withJSONObject: body)
    }
    static func uploadVideo(file: URL, manifest: VideoCaptureManifest, sensor: SensorReply) async throws {
        let body = try await Task.detached(priority: .utility) { try descriptor(file: file, manifest: manifest) }.value
        let ticket = try JSONDecoder().decode(VideoTicket.self, from: await post("videos/prepare", body: body, token: sensor.video_upload_token))
        // A previous PUT may have completed even if its response was lost.
        if let data = try? await post("videos/complete", token: ticket.receipt),
           let completion = try? JSONDecoder().decode(Completion.self, from: data),
           completion.id == sensor.id, completion.session_id == manifest.id, completion.video_complete { return }
        var request = URLRequest(url: ticket.upload_url)
        request.httpMethod = "PUT"; request.timeoutInterval = 600
        for (key, value) in ticket.headers { request.setValue(value, forHTTPHeaderField: key) }
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UploadError(text: "录像上传失败，请重试") }
        let data = try await post("videos/complete", token: ticket.receipt)
        let completion = try JSONDecoder().decode(Completion.self, from: data)
        guard completion.id == sensor.id, completion.session_id == manifest.id, completion.video_complete else {
            throw UploadError(text: "录像关联失败，请重试")
        }
    }
}
