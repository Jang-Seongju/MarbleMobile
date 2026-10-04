import Foundation

public struct InformationLine: Equatable {
    public let text: String
    public let isHeading: Bool

    public init(_ text: String, heading: Bool = false) {
        self.text = text
        self.isHeading = heading
    }
}

public enum PresentationFormatter {
    public static func profileLines(_ text: String) -> [InformationLine] {
        let headings: Set<String> = [
            "[계정 정보]", "[현재 상태]", "[기본 전적]", "[승리 유형]",
            "[누적 점수]", "[보정 평균]", "[순위 평가]"
        ]
        return text.split(whereSeparator: \.isNewline).map {
            let value = String($0)
            return InformationLine(value, heading: headings.contains(value))
        }
    }

    public static func rankingLines(_ payload: [String: Any]) -> [InformationLine] {
        guard let entries = payload["entries"] as? [[String: Any]],
              let baseline = payload["baseline"] as? [String: Any]
        else { return [.init("전체 랭킹"), .init("랭킹 정보를 표시할 수 없습니다.")] }
        var lines = [InformationLine("전체 랭킹")]
        if entries.isEmpty {
            lines.append(.init("랭킹에 표시할 완료 게임 사용자가 없습니다."))
            return lines
        }
        lines += [
            .init("[랭킹 기준]"),
            .init("랭킹 참여자 수: \(intValue(baseline["active_user_count"]))"),
            .init("기준 게임 수: \(intValue(baseline["baseline_game_count"]))"),
            .init("기준 평균 마블: \(marbleValue(baseline["baseline_average_marble_score"]))"),
            .init("기준 평균 승점: \(floatValue(baseline["baseline_average_victory_score"]))"),
            .init("[순위 목록]")
        ]
        for entry in entries {
            lines += [
                .init("\(rankValue(entry["rank"])): \(entry["nickname"] as? String ?? "")", heading: true),
                .init("총 게임 수: \(intValue(entry["total_games"]))"),
                .init("승리: \(intValue(entry["wins"]))"),
                .init("패배: \(intValue(entry["losses"]))"),
                .init("승률: \(percentValue(entry["win_rate"]))"),
                .init("누적 마블: \(marbleValue(entry["cumulative_marble"]))"),
                .init("누적 승점: \(victoryScoreValue(entry["victory_score"]))"),
                .init("보정 평균 마블: \(marbleValue(entry["adjusted_average_marble"]))"),
                .init("마블 점수: \(floatValue(entry["marble_score"]))"),
                .init("보정 평균 승점: \(floatValue(entry["adjusted_average_victory_score"]))"),
                .init("순위 평가 점수: \(floatValue(entry["ranking_score"]))")
            ]
        }
        return lines
    }

    public static func gameRecordLines(_ payload: [String: Any]) -> [InformationLine] {
        var lines = [InformationLine("한 게임 최다 획득 마블 기록")]
        let groups = payload["groups"] as? [[String: Any]] ?? []
        let typeLabels = ["triple_color": "트리플 컬러독점", "line": "라인독점", "tourist": "관광지독점"]
        for count in [4, 3, 2] {
            lines.append(.init("[\(count)인 게임 기록]", heading: true))
            let group = groups.first { number($0["participant_count"])?.intValue == count }
            let entries = group?["entries"] as? [[String: Any]] ?? []
            if entries.isEmpty { lines.append(.init("기록 없음")); continue }
            for (index, entry) in entries.enumerated() {
                lines += [
                    .init("\(number(entry["rank"])?.intValue ?? index + 1)위"),
                    .init("닉네임: \(entry["nickname"] as? String ?? "")"),
                    .init("획득 마블: \(marbleValue(entry["marble_delta"]))마블"),
                    .init("승리 방식: \(entry["victory_type"] as? String == "ending_monopoly" ? "엔딩독점" : "최후의 1인")")
                ]
                if let types = entry["ending_monopoly_types"] as? [String], !types.isEmpty {
                    lines.append(.init("엔딩독점 유형: " + types.map { typeLabels[$0] ?? $0 }.joined(separator: ", ")))
                }
                lines.append(.init("기록 일시: \(recordDateTime(entry["finished_at"]))"))
            }
        }
        return lines
    }

    private static func recordDateTime(_ value: Any?) -> String {
        guard let text = value as? String, !text.isEmpty else { return "알 수 없음" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsed = parser.date(from: text)
        if parsed == nil {
            parser.formatOptions = [.withInternetDateTime]
            parsed = parser.date(from: text)
        }
        guard let date = parsed else { return text }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 a h시 mm분"
        return formatter.string(from: date)
    }

    public static func roomInfoText(_ room: GameRoomSummary, participantNames: [String]? = nil) -> String {
        let statusLabel: String
        switch room.status {
        case "waiting": statusLabel = "대기 중"
        case "playing": statusLabel = "게임 중"
        default: statusLabel = "알 수 없음"
        }
        let currentLabel = room.current.map(String.init) ?? "알 수 없음"
        let maxLabel = room.maxPlayers.map(String.init) ?? "알 수 없음"
        let privacyLabel = room.isPrivate == true ? "비공개" : "공개"

        var lines = [
            "방 번호: \(room.id)",
            "방 제목: \(room.title)",
            "게임 상태: \(statusLabel)",
            "참여 인원: \(currentLabel)/\(maxLabel)명",
            "공개 여부: \(privacyLabel)",
            "참여 사용자:",
        ]
        if let participantNames {
            let cleaned = participantNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if cleaned.isEmpty {
                lines.append("없음")
            } else {
                for (index, name) in cleaned.enumerated() { lines.append("\(index + 1). \(name)") }
            }
        } else {
            lines.append("상세 정보 없음")
        }
        return lines.joined(separator: "\n")
    }

    public static func userProfileText(_ profile: [String: Any]) -> String {
        let account = dictionary(profile["account"])
        let stats = dictionary(profile["stats"])
        let ranking = dictionary(profile["ranking"])
        let runtime = dictionary(profile["runtime"])

        guard let nickname = nonblankString(account["nickname"]) else {
            return "사용자 정보\n\n사용자 정보를 표시할 수 없습니다."
        }

        var lines: [String] = []
        lines.append("사용자 정보: \(nickname)")
        lines.append("")
        lines.append("[계정 정보]")
        lines.append("닉네임: \(nickname)")
        if let username = nonblankString(account["username"]) { lines.append("아이디: \(username)") }
        if let createdAt = account["created_at"], !(createdAt is NSNull) {
            lines.append("가입일: \(formatDateTime(createdAt, emptyLabel: "기록 없음"))")
        }
        lines.append("최근 접속일: \(formatDateTime(account["last_connected_at"], emptyLabel: "기록 없음"))")
        lines.append("최근 종료일: \(formatDateTime(account["last_disconnected_at"], emptyLabel: "기록 없음"))")
        lines.append("")

        lines.append("[현재 상태]")
        lines.append("접속 상태: \(runtimeConnectionStatus(runtime))")
        lines.append("위치: \(runtimeLocation(runtime))")
        lines.append("")

        lines.append("[기본 전적]")
        lines.append("총 게임 수: \(intValue(stats["total_games"]))")
        lines.append("승리: \(intValue(stats["wins"]))")
        lines.append("패배: \(intValue(stats["losses"]))")
        lines.append("승률: \(percentValue(stats["win_rate"]))")
        lines.append("파산 횟수: \(intValue(stats["bankruptcies"]))")
        lines.append("")

        lines.append("[승리 유형]")
        lines.append("최종 생존 승리: \(intValue(stats["last_survivor_wins"]))")
        lines.append("엔딩 독점 승리: \(intValue(stats["ending_monopoly_wins"]))")
        lines.append("트리플 컬러독점 승리: \(intValue(stats["triple_color_ending_wins"]))")
        lines.append("라인독점 승리: \(intValue(stats["line_ending_wins"]))")
        lines.append("관광지독점 승리: \(intValue(stats["tourist_ending_wins"]))")
        lines.append("엔딩 독점 합계: \(intValue(stats["ending_monopoly_total"]))")
        lines.append("")

        lines.append("[누적 점수]")
        lines.append("누적 마블: \(marbleValue(stats["cumulative_marble"]))")
        lines.append("누적 승점: \(victoryScoreValue(stats["victory_score"]))")
        lines.append("")

        lines.append("[보정 평균]")
        lines.append("보정 평균 마블: \(marbleValue(ranking["adjusted_average_marble"]))")
        lines.append("보정 평균 승점: \(floatValue(ranking["adjusted_average_victory_score"]))")
        lines.append("")

        lines.append("[순위 평가]")
        lines.append("마블 점수: \(floatValue(ranking["marble_score"]))")
        lines.append("순위 평가 점수: \(floatValue(ranking["ranking_score"]))")
        lines.append("순위: \(rankValue(ranking["rank"]))")
        if let reason = ranking["ranking_exclusion_reason"] as? String {
            lines.append("랭킹 제외 사유: \(reason == "no_completed_games" ? "완료한 게임 없음" : "알 수 없음")")
        }
        return lines.joined(separator: "\n")
    }

    private static func dictionary(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
    private static func nonblankString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }
    private static func number(_ value: Any?) -> NSNumber? {
        WireScalarParser.nonBooleanNumber(value)
    }
    private static func intValue(_ value: Any?) -> String { String(number(value)?.intValue ?? 0) }
    private static func victoryScoreValue(_ value: Any?) -> String {
        guard let value = number(value)?.doubleValue else { return "0" }
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
    private static func percentValue(_ value: Any?) -> String { String(format: "%.2f%%", number(value)?.doubleValue ?? 0) }
    private static func floatValue(_ value: Any?) -> String {
        guard let value = number(value)?.doubleValue else { return "없음" }
        return String(format: "%.6f", value)
    }
    private static func marbleValue(_ value: Any?) -> String {
        guard let value = number(value)?.doubleValue else { return "없음" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        let isInteger = value.rounded() == value
        formatter.maximumFractionDigits = isInteger ? 0 : 2
        formatter.minimumFractionDigits = isInteger ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    private static func rankValue(_ value: Any?) -> String {
        guard let rank = number(value)?.intValue else { return "없음" }
        return "\(rank)위"
    }

    private static func runtimeConnectionStatus(_ runtime: [String: Any]) -> String {
        switch runtime["connection_status"] as? String {
        case "connected": return "접속 중"
        case "disconnected": return "접속 끊김"
        default: return "접속 상태 알 수 없음"
        }
    }

    private static func runtimeLocation(_ runtime: [String: Any]) -> String {
        let locationType = runtime["location_type"] as? String
        if locationType == "lobby" { return "대기실" }
        if locationType == "room" || locationType == "spectator" {
            guard let roomID = number(runtime["room_id"])?.intValue,
                  let roomTitle = runtime["room_title"] as? String else { return "위치 정보 없음" }
            let base = "\(roomID)번 방 '\(roomTitle)'"
            if locationType == "spectator" {
                if let nickname = nonblankString(runtime["observed_nickname"]) { return "\(base) \(nickname)의 관중석" }
                if let observedID = number(runtime["observed_user_id"])?.intValue { return "\(base) 사용자 \(observedID)의 관중석" }
                return "\(base) 관중석"
            }
            if runtime["is_game_in_progress"] as? Bool == true { return "\(base), 게임 중" }
            return base
        }
        return "위치 정보 없음"
    }

    // PC formatter는 timezone-aware 값도 local timezone으로 바꾸지 않고 응답 문자열의 벽시각을 표시한다.
    private static func formatDateTime(_ value: Any?, emptyLabel: String) -> String {
        guard !(value is NSNull), let text = value as? String, !text.isEmpty else { return emptyLabel }
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 6 else { return text }
        func group(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }
        guard let year = group(1), let month = group(2), let day = group(3), let hour24 = group(4), let minute = group(5) else { return text }
        let period = hour24 < 12 ? "오전" : "오후"
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return "\(year)년 \(month)월 \(day)일 \(period) \(hour12)시 \(String(format: "%02d", minute))분"
    }
}
