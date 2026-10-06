import Foundation

public enum RoomManagementValidationError: Error, Equatable, LocalizedError, Sendable {
    case missingTitle
    case titleTooLong
    case invalidMaxPlayers
    case belowCurrentCount(Int)
    case missingParticipants
    case missingPrivatePassword

    public var errorDescription: String? {
        switch self {
        case .missingTitle: return "방 제목을 입력해 주세요."
        case .titleTooLong: return "방 제목은 50자 이하여야 합니다."
        case .invalidMaxPlayers: return "참여 인원은 2~4명이어야 합니다."
        case .belowCurrentCount(let count): return "현재 참가자 수(\(count)명)보다 적은 인원으로 설정할 수 없습니다."
        case .missingParticipants: return "현재 방 인원 정보를 확인할 수 없습니다."
        case .missingPrivatePassword: return "비공개 방으로 변경하려면 비밀번호가 필요합니다."
        }
    }
}

/// PC 방 관리와 server(681)의 검증 계약. 빈 비밀번호는 기존 비공개 방의
/// 비밀번호 유지이며, 공개 방으로 바꾸면 서버가 저장된 비밀번호를 제거한다.
public struct RoomManagementRequest: Equatable, Sendable {
    public let title: String
    public let maxPlayers: Int
    public let isPrivate: Bool
    public let password: String?

    public init(
        title: String,
        maxPlayers: Int,
        isPrivate: Bool,
        password: String,
        currentCount: Int?,
        currentlyPrivate: Bool
    ) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw RoomManagementValidationError.missingTitle }
        guard cleanTitle.count <= 50 else { throw RoomManagementValidationError.titleTooLong }
        guard (2...4).contains(maxPlayers) else { throw RoomManagementValidationError.invalidMaxPlayers }
        guard let currentCount, currentCount >= 1 else {
            throw RoomManagementValidationError.missingParticipants
        }
        guard maxPlayers >= currentCount else {
            throw RoomManagementValidationError.belowCurrentCount(currentCount)
        }
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if isPrivate && !currentlyPrivate && cleanPassword.isEmpty {
            throw RoomManagementValidationError.missingPrivatePassword
        }
        self.title = cleanTitle
        self.maxPlayers = maxPlayers
        self.isPrivate = isPrivate
        self.password = isPrivate && !cleanPassword.isEmpty ? cleanPassword : nil
    }
}
