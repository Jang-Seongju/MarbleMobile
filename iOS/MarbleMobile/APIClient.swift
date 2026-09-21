import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct APIAuthenticationLostError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ProfileFetchResult {
    let profile: [String: Any]
    let tokens: TokenPair
}

final class APIClient {
    private let config: AppConfiguration
    init(config: AppConfiguration) { self.config = config }

    func login(username: String, password: String) async throws -> AuthenticatedSession {
        let body: [String: String] = ["username": username, "password": password]
        let (loginData, loginResponse) = try await request(path: "/auth/login", method: "POST", json: body)
        guard loginResponse.statusCode == 200 else {
            if loginResponse.statusCode == 401 { throw APIError(message: "아이디 또는 비밀번호가 올바르지 않습니다.") }
            if loginResponse.statusCode == 422 { throw APIError(message: "입력값을 확인해 주세요.") }
            throw APIError(message: "서버 오류가 발생했습니다. (\(loginResponse.statusCode))")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: loginData)
        guard !token.accessToken.isEmpty, !token.refreshToken.isEmpty else {
            throw APIError(message: "서버 응답에 인증 토큰이 없습니다.")
        }

        var meRequest = URLRequest(url: config.baseURL.appending(path: "/users/me"))
        meRequest.timeoutInterval = 10
        meRequest.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (meData, meResponse) = try await data(for: meRequest)
        guard meResponse.statusCode == 200 else { throw APIError(message: "유저 정보를 가져오지 못했습니다.") }
        let me = try JSONDecoder().decode(CurrentUser.self, from: meData)
        return AuthenticatedSession(
            identity: .init(userID: me.id, username: me.username, nickname: me.nickname),
            tokens: .init(accessToken: token.accessToken, refreshToken: token.refreshToken)
        )
    }

    func checkUsername(_ username: String) async throws -> Bool {
        try await duplicateCheck(path: "/auth/check-username", name: "username", value: username)
    }

    func checkNickname(_ nickname: String) async throws -> Bool {
        try await duplicateCheck(path: "/auth/check-nickname", name: "nickname", value: nickname)
    }

    func register(username: String, nickname: String, password: String) async throws {
        let (data, response) = try await request(
            path: "/auth/register", method: "POST",
            json: ["username": username, "nickname": nickname, "password": password]
        )
        if response.statusCode == 201 { return }
        if response.statusCode == 409 {
            let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let detail = body["detail"] as? String ?? ""
            throw APIError(message: detail.contains("Nickname") ? "이미 사용 중인 닉네임입니다." : "이미 사용 중인 아이디입니다.")
        }
        if response.statusCode == 422 { throw APIError(message: validationMessage(from: data)) }
        throw APIError(message: "서버 오류가 발생했습니다. (\(response.statusCode))")
    }

    func getProfile(userID: Int, tokens: TokenPair) async throws -> ProfileFetchResult {
        let first = try await protectedJSON(path: "/users/\(userID)/profile", accessToken: tokens.accessToken)
        if first.response.statusCode == 200 {
            return ProfileFetchResult(profile: try jsonObject(first.data, invalidMessage: "사용자 정보 형식이 올바르지 않습니다."), tokens: tokens)
        }

        let firstCode = errorCode(from: first.data)
        if first.response.statusCode == 401 && firstCode == "access_token_expired" {
            let refreshed = try await refresh(refreshToken: tokens.refreshToken)
            let second = try await protectedJSON(path: "/users/\(userID)/profile", accessToken: refreshed.accessToken)
            if second.response.statusCode == 200 {
                return ProfileFetchResult(profile: try jsonObject(second.data, invalidMessage: "사용자 정보 형식이 올바르지 않습니다."), tokens: refreshed)
            }
            if isTerminalAuth(status: second.response.statusCode, code: errorCode(from: second.data)) {
                throw APIAuthenticationLostError(message: "로그인 정보를 갱신할 수 없습니다. 다시 로그인해 주세요.")
            }
            throw profileHTTPError(status: second.response.statusCode)
        }

        if isTerminalAuth(status: first.response.statusCode, code: firstCode) {
            throw APIAuthenticationLostError(message: "로그인 정보를 갱신할 수 없습니다. 다시 로그인해 주세요.")
        }
        throw profileHTTPError(status: first.response.statusCode)
    }

    private func refresh(refreshToken: String) async throws -> TokenPair {
        guard !refreshToken.isEmpty else {
            throw APIAuthenticationLostError(message: "로그인 정보를 갱신할 수 없습니다. 다시 로그인해 주세요.")
        }
        let (data, response) = try await request(path: "/auth/refresh", method: "POST", json: ["refresh_token": refreshToken])
        guard response.statusCode == 200 else {
            let code = errorCode(from: data)
            if isTerminalAuth(status: response.statusCode, code: code) || code?.hasPrefix("refresh_token_") == true {
                throw APIAuthenticationLostError(message: "로그인 정보를 갱신할 수 없습니다. 다시 로그인해 주세요.")
            }
            throw APIError(message: "로그인 정보 갱신 요청에 실패했습니다.")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !decoded.accessToken.isEmpty, !decoded.refreshToken.isEmpty else {
            throw APIAuthenticationLostError(message: "로그인 정보를 갱신할 수 없습니다. 다시 로그인해 주세요.")
        }
        return TokenPair(accessToken: decoded.accessToken, refreshToken: decoded.refreshToken)
    }

    private func protectedJSON(path: String, accessToken: String) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: config.baseURL.appending(path: path))
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await data(for: request)
    }

    private func duplicateCheck(path: String, name: String, value: String) async throws -> Bool {
        var components = URLComponents(url: config.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: name, value: value)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        let (data, response) = try await data(for: request)
        guard response.statusCode == 200 else { throw APIError(message: "서버 오류가 발생했습니다.") }
        let decoded = try JSONDecoder().decode(DuplicateResponse.self, from: data)
        return decoded.exists
    }

    private func request(path: String, method: String, json: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: config.baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        return try await data(for: request)
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, rawResponse) = try await URLSession.shared.data(for: request)
            guard let response = rawResponse as? HTTPURLResponse else { throw APIError(message: "서버 응답이 올바르지 않습니다.") }
            return (data, response)
        } catch let error as APIError { throw error }
        catch let error as URLError where error.code == .timedOut {
            throw APIError(message: "서버 응답이 너무 늦습니다.\n접속 대상: \(config.baseURL.absoluteString)\n잠시 후 다시 시도해 주세요.")
        } catch {
            throw APIError(message: "서버에 연결할 수 없습니다.\n접속 대상: \(config.baseURL.absoluteString)\n서버 주소와 서버 실행 상태를 확인해 주세요.")
        }
    }


    private func profileHTTPError(status: Int) -> APIError {
        switch status {
        case 403: return APIError(message: "사용자 정보를 조회할 권한이 없습니다.")
        case 404: return APIError(message: "사용자를 찾을 수 없습니다.")
        case 422: return APIError(message: "요청값을 확인해 주세요.")
        default: return APIError(message: "서버 오류가 발생했습니다. (\(status))")
        }
    }

    private func errorCode(from data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = body["error"] as? [String: Any] else { return nil }
        return error["code"] as? String
    }

    private func isTerminalAuth(status: Int, code: String?) -> Bool {
        status == 401 || (status == 403 && code == "inactive_user")
    }

    private func jsonObject(_ data: Data, invalidMessage: String) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError(message: invalidMessage)
        }
        return json
    }

    private func validationMessage(from data: Data) -> String {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = body["detail"] as? [[String: Any]],
              let first = detail.first,
              let message = first["msg"] as? String else { return "입력값을 확인해 주세요." }
        return message.replacingOccurrences(of: "Value error, ", with: "")
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token" }
}
private struct CurrentUser: Decodable { let id: Int; let username: String; let nickname: String }
private struct DuplicateResponse: Decodable { let exists: Bool }
