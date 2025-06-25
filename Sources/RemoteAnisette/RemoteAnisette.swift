import Foundation
#if !canImport(Darwin)
import FoundationNetworking
#endif

import SHA2

// MARK: WebSocket async helper

final class URLSessionWebSocketStream: AsyncSequence, Sendable {
    typealias WebSocketStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>
    typealias AsyncIterator = WebSocketStream.Iterator
    typealias Element = URLSessionWebSocketTask.Message

    private nonisolated(unsafe) var continuation: WebSocketStream.Continuation?
    public let task: URLSessionWebSocketTask

    public var stream: WebSocketStream {
        WebSocketStream { continuation in
            self.continuation = continuation
            waitForNextValue()
        }
    }

    func waitForNextValue() {
        guard task.closeCode == .invalid else {
            continuation?.finish()
            return
        }

        task.receive { [weak self] result in
            guard let continuation = self?.continuation else { return }
            do {
                let message = try result.get()
                continuation.yield(message)
                self?.waitForNextValue()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
    }

    deinit {
        continuation?.finish()
    }

    func makeAsyncIterator() -> AsyncIterator {
        return stream.makeAsyncIterator()
    }

    func cancel() async throws {
        task.cancel(with: .goingAway, reason: nil)
        continuation?.finish()
    }
}

// MARK: Helper protocols/extensions

protocol JSONDecodable: Decodable {
    static var jsonDecoder: JSONDecoder { get }
}

extension JSONDecodable {
    init(json data: Data) throws { self = try Self.jsonDecoder.decode(Self.self, from: data) }
}

extension JSONSerialization {
    static func string(withJSONObject obj: Any, options opt: JSONSerialization.WritingOptions = []) throws -> String {
        let data = try data(withJSONObject: obj, options: opt)
        guard let s = String(data: data, encoding: .utf8) else { throw NSError(domain: "Invalid utf8 data", code: 0, userInfo: nil) }
        return s
    }
}

protocol PlistDecodable: Decodable {
    static var plistDecoder: PropertyListDecoder { get }
}

extension PlistDecodable {
    init(plist data: Data) throws { self = try Self.plistDecoder.decode(Self.self, from: data) }
}

extension DateFormatter {
    static let anisetteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()
}

extension Date {
    var anisetteFormat: String { DateFormatter.anisetteFormatter.string(from: self) }
}

extension Data {
    static func random(_ length: Int) -> Data {
        length > 0 ? Data((0..<length).map { _ in UInt8.random(in: 0...255) }) : Data()
    }

    var sha256Hash: String { SHA256(hashing: self).description.uppercased() }
    
    var utf8: String { String(data: self, encoding: .utf8) ?? "invalid data" }
}

// MARK: Data types

struct ErrorResponse: JSONDecodable {
    static let jsonDecoder: JSONDecoder = JSONDecoder()
    
    public let result, message: String
}
    
struct ResponseStatus: JSONDecodable {
    static let jsonEncoder: JSONEncoder = JSONEncoder()
    static let jsonDecoder: JSONDecoder = JSONDecoder()
    
    let code: Int
    let message: String
    let description: String
    
    enum CodingKeys: String, CodingKey {
        case code = "ec"
        case message = "em"
        case description = "ed"
    }
}

struct StartProvisioningResponse: PlistDecodable {
    static let plistDecoder = PropertyListDecoder()

    struct Response: PlistDecodable {
        static let plistDecoder = PropertyListDecoder()
        let status: ResponseStatus
        let spim: String
        let ptxid: UUID
        
        enum CodingKeys: String, CodingKey {
            case status = "Status"
            case spim
            case ptxid
        }
    }
    enum CodingKeys: String, CodingKey {
        case response = "Response"
    }

    let response: Response
    
    var spim: String { response.spim }
}

struct EndProvisioningResponse: PlistDecodable {
    static let plistDecoder = PropertyListDecoder()

    struct Response: PlistDecodable {
        static let plistDecoder = PropertyListDecoder()
        let status: ResponseStatus
        let rinfo: String
        let tk: String
        let ptm: String
        let ptxid: UUID
        
        enum CodingKeys: String, CodingKey {
            case status = "Status"
            case rinfo = "X-Apple-I-MD-RINFO"
            case tk
            case ptm
            case ptxid
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case response = "Response"
    }

    let response: Response
    
    var tk: String { response.tk }
    var ptm: String { response.ptm }
    
}

struct AnisetteV3Message: JSONDecodable {
    static let jsonDecoder: JSONDecoder = JSONDecoder()
    
    let result: String
    
    enum Step {
        case identifier, start, end, success, timeout, error(String)
    }
    
    var step: Step {
        switch result {
        case "GiveIdentifier": .identifier
        case "GiveStartProvisioningData": .start
        case "GiveEndProvisioningData": .end
        case "ProvisioningSuccess": .success
        case "Timeout": .timeout
        default: .error(result)
        }
    }
}

struct AnisetteV3EndMessage: JSONDecodable {
    static let jsonDecoder: JSONDecoder = JSONDecoder()
    
    let cpim: String
}

struct AnisetteV3SuccessMessage: JSONDecodable {
    static let jsonDecoder: JSONDecoder = JSONDecoder()
    
    let adi_pb: String
}

struct ProvisioningURLs: PlistDecodable, Sendable {
    static let plistDecoder = PropertyListDecoder()
    
    struct URLs: PlistDecodable {
        static let plistDecoder = PropertyListDecoder()
        
        let start, end: String
        
        enum CodingKeys: String, CodingKey {
            case start = "midStartProvisioning"
            case end = "midFinishProvisioning"
        }
    }
    
    let urls: URLs
    
    var start: URL { URL(string: urls.start)! }
    var end: URL { URL(string: urls.end)! }
}

struct AnisetteV3Response: JSONDecodable {
    static let jsonDecoder: JSONDecoder = JSONDecoder()
    
    public enum CodingKeys: String, CodingKey {
        case oneTimePassword = "X-Apple-I-MD"
        case machineID       = "X-Apple-I-MD-M"
        case routingInfo     = "X-Apple-I-MD-RINFO"
    }

    public let oneTimePassword, machineID, routingInfo: String
}

// MARK: AnisetteUser

/// Each AnisetteUser is a unique "device" that gets added to an Apple ID
public struct AnisetteUser: Codable, Sendable {
    /// The anisette v3 server's URL endpoint
    public let url: URL
    /// The "device" to mock as when creating requests
    public let client_info: String
    /// The process to mock as e.g. "akd/1.0"
    public let user_agent: String
    /// The serial number to mock when creating requests 
    /// - Can be phony as long as the "device" is trusted
    public let serial: String
    /// The local user ID to use when creating requests
    public let localUserID: String
    /// The Mahine ID to use when creating requests
    public let deviceID: String
    
    /// Personalization data required for anisette generation
    public private(set) var adiPB: String?
    /// The start and end URLs required for provisioning
    private var provisioningURLs: ProvisioningURLs?
    /// The URLSession to use when creating requests
    private var session: URLSession = .shared

    enum CodingKeys: String, CodingKey {
        case url, client_info, user_agent, serial, localUserID, deviceID, adiPB
    }
    
    public init(
        url: URL? = nil,
        client_info: String? = nil,
        user_agent: String? = nil,
        serial: String? = nil,
        local: String? = nil,
        device: String? = nil,
        adiPB: String? = nil,
        session: URLSession = .shared
    ) {
        self.url = url ?? URL(string: "https://ani.sidestore.io")!
        self.client_info = client_info ?? "<MacBookPro13,2> <macOS;13.1;22C65> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>"
        self.user_agent = user_agent ?? "akd/1.0 CFNetwork/808.1.4"
        self.serial = serial ?? "0"
        self.localUserID = local ?? Data.random(16).base64EncodedData().sha256Hash
        self.deviceID = device ?? UUID().uuidString.uppercased()
        self.adiPB = adiPB
        self.session = session
    }
    
    /// Provides anisette headers from the v3 server specified at `url`
    ///
    /// - Returns: HTTP headers as key value pairs
    public func fetchHeaders() async throws -> [String: String] {
        let ani = try await fetchV3Anisette()
        return [
            "X-Apple-Client-Time": Date().anisetteFormat,
            "X-Apple-I-TimeZone": Calendar.current.timeZone.abbreviation() ?? "UTC",
            "X-Apple-Locale": Locale.current.identifier,
            "X-Apple-I-MD": ani.oneTimePassword,
            "X-Apple-I-MD-LU": localUserID,
            "X-Apple-I-MD-M": ani.machineID,
            "X-Apple-I-MD-RINFO": ani.routingInfo,
            "X-Apple-I-SRL-NO": serial,
            "X-Mme-Drvice-Id": deviceID,
        ]
    }
    
    func fetchV3Anisette() async throws -> AnisetteV3Response {
        guard let adiPB = adiPB else { throw AnisetteError.missingAdiPb }
        var request = URLRequest(url: url.appendingPathComponent("v3/get_headers"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["identifier": localUserID, "adi_pb": adiPB])
        let data = try await session.data(for: request).0
        do {
            return try AnisetteV3Response(json: data)
        } catch {
            guard let resp = try? ErrorResponse(json: data) else {
                throw error
            }
            throw AnisetteError.serverError("\(resp.result) - \(resp.message)")
        }
    }
    
    func buildAppleRequest(url: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue(client_info, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(user_agent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(localUserID, forHTTPHeaderField: "X-Mme-Device-Id")
        request.setValue(Date().anisetteFormat, forHTTPHeaderField: "X-Apple-I-Client-Time")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "X-Apple-Locale")
        request.setValue(Calendar.current.timeZone.abbreviation() ?? "UTC", forHTTPHeaderField: "X-Apple-I-TimeZone")

        return request
    }
    
    mutating func fetchProvisioningURLs() async {
        provisioningURLs = try? ProvisioningURLs(plist: try await session.data(for: buildAppleRequest(url: "https://gsa.apple.com/grandslam/GsService2/lookup")).0)
    }
    
    lazy var provisioningRequest: URLRequest = {
        var request = URLRequest(url: URL(string: "wss://" + url.host!)!.appendingPathComponent("v3/provisioning_session"))
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        return request
    }()
    
    /// Provisions the "device" for use with anisette generation
    /// 
    /// Sets the adiPB attribute, does not run if adiPB is already set
    public mutating func provision() async throws {
        guard adiPB == nil else { return }
        await fetchProvisioningURLs()
        guard provisioningURLs != nil else { return }
        let stream = URLSessionWebSocketStream(task: session.webSocketTask(with: provisioningRequest))
        for try await message in stream.stream {
            switch message {
            case .string(let string):
                if let d = string.data(using: .utf8),
                   let resp = try? AnisetteV3Message(json: d) {
                    switch resp.step {
                    case .identifier: try await sendIdentifier(task: stream.task)
                    case .start: try await startProvisioning(task: stream.task)
                    case .end: try await endProvisioning(task: stream.task, try AnisetteV3EndMessage(json: d).cpim)
                    case .success: adiPB = try AnisetteV3SuccessMessage(json: d).adi_pb
                    case .timeout: print("Timeout..")
                    case .error(let error): print("Error: \(error)")
                    }
                }
            case .data(_): fallthrough
            @unknown default: break
            }
        }
    }

    func buildPlistBody(_ req: [String: String] = [:]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["Header": [String: String](), "Request": req], format: .xml, options: 0)
    }
    
    func sendIdentifier(task: URLSessionWebSocketTask) async throws {
        try await task.send(.string(try JSONSerialization.string(withJSONObject: ["identifier": localUserID])))
    }
    
    func startProvisioning(task: URLSessionWebSocketTask) async throws {
        guard let provURLs = provisioningURLs else { throw AnisetteError.invalidProvisioningURLs }
        var req = buildAppleRequest(url: provURLs.start.absoluteString)
        req.httpMethod = "POST"
        req.httpBody = try buildPlistBody()
        let data = try StartProvisioningResponse(plist: try await session.data(for: req).0)
        let body = try JSONSerialization.string(withJSONObject: ["spim": data.spim])
        try await task.send(.string(body))
    }
    
    func endProvisioning(task: URLSessionWebSocketTask, _ cpim: String) async throws {
        guard let provURLs = provisioningURLs else { throw AnisetteError.invalidProvisioningURLs }
        var req = buildAppleRequest(url: provURLs.end.absoluteString)
        req.httpMethod = "POST"
        req.httpBody = try buildPlistBody(["cpim": cpim])

        let data = try EndProvisioningResponse(plist: try await session.data(for: req).0)
        let body = try JSONSerialization.string(withJSONObject: ["ptm": data.ptm, "tk": data.tk])
        try await task.send(.string(body))
    }
}

// MARK: - Error Types

public enum AnisetteError: LocalizedError {
    case noServerFound
    case invalidProvisioningURLs
    case invalidClientInfo
    case missingUserAgent
    case identifierGenerationFailed
    case missingIdentifier
    case missingClientInfo
    case invalidAnisetteFormat
    case invalidAnisetteData
    case headerError(String)
    case unknownMessageType
    case invalidServerResponse
    case missingCpim
    case missingAdiPb
    case missingProvisioningURL
    case invalidStartProvisioningData
    case invalidEndProvisioningData
    case serverError(String)
    case noAccountSelected
    
    public var errorDescription: String {
        switch self {
        case .noServerFound:
            return "No Anisette Server Found!"
        case .invalidProvisioningURLs:
            return "Apple didn't give valid URLs. Please try again later."
        case .invalidClientInfo:
            return "Couldn't fetch client info. The returned data may not be in JSON."
        case .missingUserAgent:
            return "User agent is missing from client info."
        case .identifierGenerationFailed:
            return "Couldn't generate identifier."
        case .missingIdentifier:
            return "Identifier is missing."
        case .missingClientInfo:
            return "Client info is missing."
        case .invalidAnisetteFormat:
            return "Invalid anisette (the returned data may not be in JSON)."
        case .invalidAnisetteData:
            return "Invalid anisette (the returned data may not have all the required fields)."
        case .headerError(let message):
            return "Header error: \(message)"
        case .unknownMessageType:
            return "Unknown WebSocket message type received."
        case .invalidServerResponse:
            return "Invalid server response."
        case .missingCpim:
            return "The server didn't provide a cpim."
        case .missingAdiPb:
            return "The server didn't provide an adi.pb file."
        case .missingProvisioningURL:
            return "Provisioning URL is missing."
        case .invalidStartProvisioningData:
            return "Apple didn't give valid start provisioning data."
        case .invalidEndProvisioningData:
            return "Apple didn't give valid end provisioning data."
        case .serverError(let message):
            return "Server error: \(message)"
        case .noAccountSelected:
            return "No account selected. Please select an account before getting anisette data."
        }
    }
}
