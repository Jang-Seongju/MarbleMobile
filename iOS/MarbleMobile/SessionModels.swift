import Foundation

struct SessionIdentity: Equatable {
    let userID: Int
    let username: String
    let nickname: String
}

struct TokenPair: Equatable {
    var accessToken: String
    var refreshToken: String
}

struct AuthenticatedSession: Equatable {
    var identity: SessionIdentity
    var tokens: TokenPair
}
