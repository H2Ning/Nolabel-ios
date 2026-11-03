import Foundation

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
    case network
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
}

struct AccountAPI {
    static let baseURL = URL(string: "https://h2ning.com")!
    static let appKey = "nolabel"
    static let dataKey = "bills"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 22
        configuration.timeoutIntervalForResource = 35
        return URLSession(configuration: configuration)
    }()

    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else {
            throw AccountError.network
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Nolabel-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AccountError.network
            }
            return (data, http)
        } catch let error as AccountError {
            throw error
        } catch {
            throw AccountError.network
        }
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
        guard let url = components?.url else { throw AccountError.network }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Nolabel-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw AccountError.network
        }
        guard let http = response as? HTTPURLResponse else { throw AccountError.network }
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
