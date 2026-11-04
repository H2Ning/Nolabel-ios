import Darwin
import Foundation
import OSLog

struct AccountUser: Equatable {
    let id: String?
    let name: String

    init(id: String?, name: String) {
        self.id = id
        self.name = name
    }

    init?(dictionary: [String: Any]) {
        let rawID = dictionary["id"]
        let rawName = dictionary["name"] ?? dictionary["username"]
        guard let name = rawName as? String, !name.isEmpty else { return nil }
        self.id = rawID.map { String(describing: $0) }
        self.name = name
    }
}

enum AccountError: Error, LocalizedError {
    case unauthorized
    case network(URLError?)
    case server(String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "登录已过期，请重新登录"
        case .network:
            "网络错误，请重试"
        case .server(let message):
            message ?? "账号操作失败"
        }
    }

    var isNetwork: Bool {
        if case .network = self { return true }
        return false
    }

    var failureReason: String? {
        switch self {
        case .network(let error):
            guard let error else { return "URLError unknown" }
            var parts = ["URLError \(error.code.rawValue)"]
            if let url = error.failingURL?.absoluteString {
                parts.append(url)
            }
            let nsError = error as NSError
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                parts.append("\(underlying.domain) \(underlying.code)")
            }
            parts.append(error.localizedDescription)
            return parts.joined(separator: " · ")
        default:
            return nil
        }
    }
}

struct AccountAPI {
    static let baseURL = URL(string: "https://www.h2ning.com")!
    static let appKey = "nolabel"
    static let dataKey = "bills"

    private static let logger = Logger(subsystem: "com.h2ning.nolabel", category: "network")

    private static let userAgent = "Nolabel-iOS/1.5"

    /// A fresh session per attempt. On a Chinese iPhone the first request can
    /// arrive while the system's "allow wireless data" sheet is up; a session
    /// created in that state can stay wedged after the user allows access.
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = true
        configuration.httpAdditionalHeaders = [
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": "https://www.h2ning.com/"
        ]
        return URLSession(
            configuration: configuration,
            delegate: PinnedTrustDelegate.shared,
            delegateQueue: nil
        )
    }

    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        attempts: Int = 3
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else {
            Self.logger.error("Could not build URL for \(path, privacy: .public)")
            throw AccountError.network(nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let total = max(1, attempts)
        var lastError: URLError?
        for attempt in 1...total {
            let session = Self.makeSession()
            defer { session.finishTasksAndInvalidate() }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AccountError.network(nil)
                }
                return (data, http)
            } catch let error as URLError {
                lastError = error
                Self.logger.error("Request \(path, privacy: .public) failed on attempt \(attempt)/\(total): code=\(error.code.rawValue) \(error.localizedDescription, privacy: .public)")
                guard attempt < total, Self.isTransient(error) else {
                    throw AccountError.network(error)
                }
                try? await Task.sleep(nanoseconds: UInt64(350_000_000 * attempt))
            } catch let error as AccountError {
                throw error
            } catch {
                Self.logger.error("Request \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                throw AccountError.network(nil)
            }
        }
        throw AccountError.network(lastError)
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .resourceUnavailable:
            true
        default:
            false
        }
    }

    private static func perform(_ request: URLRequest, path: String) async throws -> (Data, HTTPURLResponse) {
        var lastError: URLError?
        for attempt in 1...3 {
            let session = makeSession()
            defer { session.finishTasksAndInvalidate() }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AccountError.network(nil)
                }
                return (data, http)
            } catch let error as URLError {
                lastError = error
                logger.error("Request \(path, privacy: .public) failed on attempt \(attempt)/3: code=\(error.code.rawValue) \(error.localizedDescription, privacy: .public)")
                guard attempt < 3, isTransient(error) else {
                    throw AccountError.network(error)
                }
                try? await Task.sleep(nanoseconds: UInt64(350_000_000 * attempt))
            }
        }
        throw AccountError.network(lastError)
    }

    private func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func message(from data: Data) -> String? {
        json(data)?["message"] as? String
    }

    func me() async throws -> AccountUser? {
        let (data, response) = try await request(path: "/api/auth/me")
        if response.statusCode == 401 {
            return nil
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AccountError.server(message(from: data))
        }
        guard let object = json(data),
              (object["ok"] as? Bool) == true,
              let userObject = object["user"] as? [String: Any] else {
            return nil
        }
        return AccountUser(dictionary: userObject)
    }

    @discardableResult
    func login(username: String, password: String) async throws -> AccountUser {
        let (data, response) = try await request(
            path: "/api/auth/login",
            method: "POST",
            body: [
                "username": username,
                "password": password,
                "remember": true
            ]
        )
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 {
                throw AccountError.server("用户名或密码错误")
            }
            throw AccountError.server(message(from: data))
        }
        guard let object = json(data),
              (object["ok"] as? Bool) == true,
              let userObject = object["user"] as? [String: Any],
              let user = AccountUser(dictionary: userObject) else {
            throw AccountError.server(message(from: data))
        }
        return user
    }

    func logout() async throws {
        let (data, response) = try await request(
            path: "/api/auth/logout",
            method: "POST",
            body: [:]
        )
        guard (200..<300).contains(response.statusCode) else {
            throw AccountError.server(message(from: data))
        }
    }

    func fetchBills() async throws -> BillsEnvelope? {
        var components = URLComponents(
            url: URL(string: "/api/user/get", relativeTo: Self.baseURL)!,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "app", value: Self.appKey),
            URLQueryItem(name: "key", value: Self.dataKey)
        ]
        guard let url = components?.url else { throw AccountError.network(nil) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let result: (Data, HTTPURLResponse)
        do {
            result = try await Self.perform(request, path: "/api/user/get")
        } catch let error as URLError {
            throw AccountError.network(error)
        } catch {
            throw error
        }
        let data = result.0
        let http = result.1
        if http.statusCode == 401 { throw AccountError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw AccountError.server(message(from: data))
        }
        guard let object = json(data),
              (object["ok"] as? Bool) == true else {
            throw AccountError.server(message(from: data))
        }
        guard let value = object["value"], !(value is NSNull) else { return nil }
        if let raw = value as? String {
            return BillsCodec.parse(raw)
        }
        if let encoded = try? JSONSerialization.data(withJSONObject: value),
           let raw = String(data: encoded, encoding: .utf8) {
            return BillsCodec.parse(raw)
        }
        return nil
    }

    /// The system may answer with a private address when a VPN, Tailscale,
    /// captive portal or router DNS rewrites the host name. iOS then shows the
    /// local-network permission sheet and the public API is unreachable.
    static func privateNetworkAddress() -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var head: UnsafeMutablePointer<addrinfo>?
        guard let host = baseURL.host,
              getaddrinfo(host, "443", &hints, &head) == 0,
              let head else {
            return nil
        }
        defer { freeaddrinfo(head) }

        var pointer: UnsafeMutablePointer<addrinfo>? = head
        while let info = pointer {
            if let address = info.pointee.ai_addr {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = buffer.withUnsafeMutableBufferPointer { raw in
                    getnameinfo(
                        address,
                        info.pointee.ai_addrlen,
                        raw.baseAddress,
                        socklen_t(raw.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }
                if status == 0 {
                    let ip = buffer.withUnsafeBufferPointer { raw in
                        String(cString: raw.baseAddress!)
                    }
                    if isPrivateAddress(ip) {
                        return ip
                    }
                }
            }
            pointer = info.pointee.ai_next
        }
        return nil
    }

    private static func isPrivateAddress(_ ip: String) -> Bool {
        let value = ip.lowercased()
        if value.hasPrefix("fe80:") || value.hasPrefix("fc") || value.hasPrefix("fd") {
            return true
        }
        let ipv4 = value.split(separator: ":").last.map(String.init) ?? value
        let parts = ipv4.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        let (a, b) = (parts[0], parts[1])
        if a == 10 { return true }
        if a == 172, (16...31).contains(b) { return true }
        if a == 192, b == 168 { return true }
        if a == 169, b == 254 { return true }
        if a == 100, (64...127).contains(b) { return true }
        return false
    }

    func saveBills(_ bills: [Bill], updatedAt: Double) async throws {
        let raw = BillsCodec.raw(bills, updatedAt: updatedAt)
        let (data, response) = try await request(
            path: "/api/user/set",
            method: "POST",
            body: [
                "app": Self.appKey,
                "key": Self.dataKey,
                "value": raw
            ]
        )
        if response.statusCode == 401 { throw AccountError.unauthorized }
        guard (200..<300).contains(response.statusCode),
              let object = json(data),
              (object["ok"] as? Bool) == true else {
            throw AccountError.server(message(from: data))
        }
    }
}
