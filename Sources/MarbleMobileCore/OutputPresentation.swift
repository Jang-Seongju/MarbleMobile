import Foundation

public enum PresentationCompletionPolicy: String, Equatable, Sendable {
    case wait
    case startOnly
}

public enum PresentationQueuePolicy: String, Equatable, Sendable {
    case enqueue
    case interrupt
    case userInputInterrupt
}

public enum PresentationInterruptRetention: String, Equatable, Sendable {
    case dropPending
    case preservePending
}

public enum PresentationCategory: String, Equatable, Sendable {
    case gameplay
    case chat
    case systemUI
}

public indirect enum PresentationNode: Equatable, Sendable {
    case tts(String)
    case voice(clip: String, fallbackTTS: String?)
    case sfx(clip: String, completion: PresentationCompletionPolicy)
    case bgmPlay(clip: String, loop: Bool)
    case bgmStop
    case delay(milliseconds: Int)
    case sequence([PresentationNode])
    case parallel([PresentationNode])
}

public struct PresentationPlan: Equatable, Sendable {
    public let root: PresentationNode
    public let category: PresentationCategory
    public let queuePolicy: PresentationQueuePolicy
    public let persistentNotice: String?
    public let interruptRetention: PresentationInterruptRetention

    public init(
        root: PresentationNode,
        category: PresentationCategory,
        queuePolicy: PresentationQueuePolicy = .enqueue,
        persistentNotice: String? = nil,
        interruptRetention: PresentationInterruptRetention = .dropPending
    ) {
        self.root = root
        self.category = category
        self.queuePolicy = queuePolicy
        self.persistentNotice = persistentNotice
        self.interruptRetention = interruptRetention
    }

    public static func gameEvent(_ message: String, root: PresentationNode? = nil) -> PresentationPlan {
        PresentationPlan(
            root: root ?? .tts(message),
            category: .gameplay,
            queuePolicy: .enqueue,
            persistentNotice: message,
            interruptRetention: .preservePending
        )
    }

    public static func systemTTS(
        _ message: String,
        queuePolicy: PresentationQueuePolicy = .enqueue,
        persistentNotice: String? = nil,
        preservePending: Bool = false
    ) -> PresentationPlan {
        PresentationPlan(
            root: .tts(message),
            category: .systemUI,
            queuePolicy: queuePolicy,
            persistentNotice: persistentNotice,
            interruptRetention: preservePending ? .preservePending : .dropPending
        )
    }
}

/// game_state.cities는 server(677)의 CITY_INFO_SPEC으로 직렬화된
/// InformationInfo 그 자체다. 모바일 전용 도시 DTO를 두지 않는다.
public typealias GameCityStateSnapshot = InformationInfo

public struct GamePresentationContext: Equatable, Sendable {
    public let localPlayerID: Int?
    public let players: [GamePlayerSnapshot]
    public let boardCatalog: BoardCatalogSnapshot?
    public let cities: [GameCityStateSnapshot]

    public init(
        localPlayerID: Int?,
        players: [GamePlayerSnapshot],
        boardCatalog: BoardCatalogSnapshot?,
        cities: [GameCityStateSnapshot] = []
    ) {
        self.localPlayerID = localPlayerID
        self.players = players
        self.boardCatalog = boardCatalog
        self.cities = cities
    }

    public func isLocal(_ playerID: Int?) -> Bool {
        guard let playerID, let localPlayerID else { return false }
        return playerID == localPlayerID
    }

    public func playerName(_ playerID: Int?, mine: String = "당신") -> String {
        guard let playerID else { return "플레이어" }
        if isLocal(playerID) { return mine }
        return players.first(where: { $0.playerID == playerID })?.nickname ?? "플레이어 \(playerID)"
    }

    public func cityName(_ cityID: Int?) -> String {
        guard let cityID else { return "알 수 없는 도시" }
        if let state = cities.first(where: { $0.cityID == cityID }), let name = state.cityName, !name.isEmpty { return name }
        if let cell = boardCatalog?.cells.first(where: { $0.cityID == cityID }) { return cell.name }
        return "도시 \(cityID)"
    }

    public func cellName(_ index: Int?) -> String {
        guard let index else { return "알 수 없는 칸" }
        return boardCatalog?.cell(at: index)?.name ?? "\(index)번 칸"
    }

    public func ownerID(of cityID: Int?) -> Int? {
        guard let cityID else { return nil }
        return cities.first(where: { $0.cityID == cityID })?.ownerID
    }
}

public enum KoreanPresentationText {
    public static func marble(_ amount: Int?) -> String {
        let number = amount ?? 0
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.maximumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: number)) ?? String(number))마블"
    }

    public static func subject(_ text: String) -> String {
        if text == "나" || text == "내" || text == "당신" { return "당신이" }
        return particle(text, batchim: "이", vowel: "가")
    }

    public static func object(_ text: String) -> String {
        particle(text, batchim: "을", vowel: "를")
    }

    public static func conjunction(_ text: String) -> String {
        particle(text, batchim: "과", vowel: "와")
    }

    private static func particle(_ text: String, batchim: String, vowel: String) -> String {
        "\(text)\(hasBatchim(text) ? batchim : vowel)"
    }

    private static func hasBatchim(_ text: String) -> Bool {
        let digitsWithBatchim = Set("013678")
        let latinWithBatchim = Set("FLMNRSXZ")
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines).reversed() {
            guard let scalar = character.unicodeScalars.first else { continue }
            let code = Int(scalar.value)
            if (0xAC00...0xD7A3).contains(code) { return (code - 0xAC00) % 28 != 0 }
            if character.isNumber { return digitsWithBatchim.contains(character) }
            let upper = Character(String(character).uppercased())
            if upper.isLetter { return latinWithBatchim.contains(upper) }
        }
        return false
    }
}

public enum GameNotificationPresenter {
    public static func build(
        notificationType type: String,
        payload: [String: Any],
        context: GamePresentationContext
    ) -> PresentationPlan? {
        switch type {
        case "arrived": return arrived(payload, context)
        case "toll_paid": return tollPaid(payload, context)
        case "city_purchased": return cityPurchased(payload, context)
        case "flag_installed": return flagInstalled(payload, context)
        case "city_acquired": return cityAcquired(payload, context)
        case "building_built": return buildingBuilt(payload, context)
        case "building_destroyed": return buildingDestroyed(payload, context)
        case "city_donated": return cityDonated(payload, context)
        case "city_changed": return cityChanged(payload, context)
        case "city_force_sold": return cityForceSold(payload, context)
        case "attack_defended": return attackDefended(payload, context)
        case "sponsorship_paid": return sponsorshipPaid(payload, context)
        case "sponsorship_received": return sponsorshipReceived(payload, context)
        case "city_effect_activated": return cityEffectActivated(payload, context)
        case "city_effect_released": return cityEffectReleased(payload, context)
        case "toll_defended": return tollDefended(payload, context)
        case "island_building_updated": return islandBuildingUpdated(payload, context)
        case "beach_building_updated": return beachBuildingUpdated(payload, context)
        case "salary_paid": return salaryPaid(payload, context)
        case "tax_paid": return taxPaid(payload, context)
        case "player_bankrupt": return playerBankrupt(payload, context)
        case "color_monopoly_achieved": return colorMonopoly(payload, context, achieved: true)
        case "color_monopoly_broken": return colorMonopoly(payload, context, achieved: false)
        case "game_over": return gameOver(payload, context)
        case "turn_started": return turnStarted(payload, context)
        case "turn_activated", "turn_ended", "player_escaped_island": return nil
        case "world_travel_started": return worldTravelStarted(payload, context)
        case "stranded_roll_failed": return strandedRollFailed(payload, context)
        case "player_stranded": return playerStranded(payload, context)
        case "olympic_hosted": return olympicHosted(payload, context)
        case "bonus_game_challenge_started": return bonusChallenge(payload, context)
        case "bonus_game_result": return bonusResult(payload)
        case "bonus_game_reward_paid": return bonusReward(payload, context)
        case "bonus_game_entry_cost_refunded": return bonusRefund(payload)
        case "error_occurred": return interruptReason(payload, context, key: "error_code")
        case "card_held": return cardHeld(payload, context)
        case "bail_payment_selection_changed": return bailSelection(payload, context)
        case "held_card_use_selection_changed": return heldCardSelection(payload, context)
        case "bail_paid": return bailPaid(payload, context)
        case "player_effect_activated": return playerEffect(payload, context)
        case "roll_dice_rejected": return interruptReason(payload, context, key: "reason_code")
        case "interaction_presentation": return interactionPresentation(payload, context)
        case "interaction_presentation_activated": return interactionPresentationActivated(payload)
        default:
            // client(393) NotificationPresenter와 동일하게 미등록 notification은
            // 임의 message fallback 없이 무시한다. 서버 사실을 모바일이 새로
            // presentation 규칙으로 만들어 내지 않는다.
            return nil
        }
    }

    private static func arrived(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), let index = int(p["to_index"]) else { return nil }
        let die1 = int(p["die1"]) ?? 0
        let die2 = int(p["die2"]) ?? 0
        let isDouble = bool(p["is_double"]) ?? false
        let name = c.playerName(playerID)
        let location = c.cellName(index)
        let diceText = die1 > 0 ? (isDouble ? "더블 \(die1 + die2)" : "\(die1 + die2)") : ""
        let message = "[\(name)] \(diceText) → \(location)".replacingOccurrences(of: "]  →", with: "] →")
        let arrivalTTS = "[\(name)] \(location)"
        var nodes: [PresentationNode] = []
        if die1 > 0 {
            nodes.append(.sfx(clip: "dice_roll.wav", completion: .wait))
            nodes.append(contentsOf: diceVoiceNodes(die1: die1, die2: die2, isDouble: isDouble, playerName: name))
            nodes.append(.sfx(clip: "move_step_\(die1 + die2).wav", completion: .wait))
            nodes.append(.tts(arrivalTTS))
        } else {
            nodes.append(.tts(message))
        }
        if c.boardCatalog?.cell(at: index)?.cellType == "FORTUNE_CARD" {
            nodes.append(.voice(clip: "fortune_card.wav", fallbackTTS: nil))
        }
        if c.isLocal(playerID) {
            if c.boardCatalog?.cell(at: index)?.cellType == "WORLD_TRAVEL" {
                nodes.append(.bgmPlay(clip: "airport_world.mp3", loop: true))
            } else {
                nodes.append(.bgmStop)
            }
        }
        return .gameEvent(message, root: .sequence(nodes))
    }

    private static func tollPaid(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let payerID = int(p["player_id"]), let ownerID = int(p["owner_id"]) else { return nil }
        let amount = int(p["amount"]) ?? 0
        guard amount > 0 else { return nil }
        let message = "\(c.playerName(payerID)) \(c.playerName(ownerID))에게 통행료 \(KoreanPresentationText.marble(amount)) 지불"
        if c.isLocal(payerID) { return .gameEvent(message, root: .parallel([.sfx(clip: "money_out.wav", completion: .wait), .tts(message)])) }
        if c.isLocal(ownerID) { return .gameEvent(message, root: .parallel([.sfx(clip: "money_in.wav", completion: .wait), .tts(message)])) }
        return .gameEvent(message)
    }

    private static func cityPurchased(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), let cityID = int(p["city_id"]) else { return nil }
        let message = "\(KoreanPresentationText.subject(c.playerName(playerID))) \(KoreanPresentationText.object(c.cityName(cityID))) \(KoreanPresentationText.marble(int(p["cost"])))에 구매했습니다"
        return .gameEvent(message)
    }

    private static func flagInstalled(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let cityID = int(p["city_id"]) else { return nil }
        return .gameEvent("\(c.cityName(cityID)) 깃발 설치")
    }

    private static func cityAcquired(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), let cityID = int(p["city_id"]) else { return nil }
        let message = "\(KoreanPresentationText.subject(c.playerName(playerID))) \(KoreanPresentationText.object(c.cityName(cityID))) 인수했습니다"
        let reaction = c.ownerID(of: cityID) == c.localPlayerID && !c.isLocal(playerID) ? "oh_no.wav" : "acquisition.wav"
        return .gameEvent(message, root: .sequence([.voice(clip: reaction, fallbackTTS: nil), .tts(message)]))
    }

    private static func buildingBuilt(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), let cityID = int(p["city_id"]) else { return nil }
        let buildings = strings(p["building_types"])
        let message = "\(KoreanPresentationText.subject(c.playerName(playerID))) \(c.cityName(cityID))에 \(buildings.joined(separator: ", ")) 건설"
        let speech: PresentationNode = buildings.contains("랜드마크")
            ? .sequence([.voice(clip: "landmark.wav", fallbackTTS: nil), .tts(message)])
            : .tts(message)
        return .gameEvent(message, root: .parallel([.sfx(clip: "construction.wav", completion: .wait), speech]))
    }

    private static func buildingDestroyed(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let cityID = int(p["city_id"]) else { return nil }
        let type = (p["building_type"] as? String) ?? ""
        let label = ["hotel":"호텔", "building":"빌딩", "villa":"빌라"][type] ?? type
        let attack = p["attack_type"] as? String
        let attackerID = int(p["attacker_player_id"])

        // client(393): 외계인 침공은 첫 이벤트에 전체 파괴 결과를 함께
        // 받아 한 문장으로만 출력하고, 같은 batch의 후속 개별 이벤트는
        // 텍스트/TTS/SFX 모두 억제한다.
        if attack == "alien_invasion",
           let batchItems = p["attack_batch_items"] as? [[String: Any]],
           !batchItems.isEmpty {
            guard bool(p["attack_effect_primary"]) == true else { return nil }
            let formatted: [(String, String)] = batchItems.compactMap { item in
                guard let batchCityID = int(item["city_id"]) else { return nil }
                let batchType = (item["building_type"] as? String) ?? ""
                let batchLabel = ["hotel":"호텔", "building":"빌딩", "villa":"빌라"][batchType] ?? batchType
                guard !batchLabel.isEmpty else { return nil }
                return (c.cityName(batchCityID), batchLabel)
            }
            guard !formatted.isEmpty else { return nil }
            let uniqueTypes = Set(formatted.map { $0.1 })
            let detail: String
            if uniqueTypes.count == 1, let kind = formatted.first?.1 {
                detail = "\(formatted.map { $0.0 }.joined(separator: ", ")) \(kind) 파괴"
            } else {
                detail = "\(formatted.map { "\($0.0) \($0.1)" }.joined(separator: ", ")) 파괴"
            }
            let attacker = attackerID.map { c.playerName($0) } ?? ""
            let message = attacker.isEmpty
                ? "외계인 침공으로 \(detail)"
                : "\(attacker)의 외계인 침공 공격으로 \(detail)"
            let isMine = batchItems.contains { item in
                guard let batchCityID = int(item["city_id"]) else { return false }
                return c.ownerID(of: batchCityID) == c.localPlayerID
            }
            let speech: PresentationNode = isMine
                ? .sequence([.voice(clip: "oh_no.wav", fallbackTTS: nil), .tts(message)])
                : .tts(message)
            return .gameEvent(message, root: .parallel([
                .sfx(clip: "destruction.wav", completion: .wait),
                speech
            ]))
        }

        let attackLabel = ["earthquake":"지진", "alien_invasion":"외계인 침공"][attack ?? ""]
        let city = c.cityName(cityID)
        let message: String
        if let attackLabel {
            let attacker = attackerID.map { c.playerName($0) } ?? ""
            message = attacker.isEmpty ? "\(attackLabel)으로 \(city) \(label) 파괴" : "\(attacker)의 \(attackLabel) 공격으로 \(city) \(label) 파괴"
        } else {
            message = "\(city) \(label) 파괴"
        }
        let isMine = c.ownerID(of: cityID) == c.localPlayerID
        let speech: PresentationNode = isMine ? .sequence([.voice(clip: "oh_no.wav", fallbackTTS: nil), .tts(message)]) : .tts(message)
        let playAttackSFX = attack != nil && (p["attack_effect_primary"] == nil || bool(p["attack_effect_primary"]) == true)
        if playAttackSFX, attack == "earthquake" { return .gameEvent(message, root: .parallel([.sfx(clip: "earthquake.wav", completion: .wait), speech])) }
        if playAttackSFX, attack == "alien_invasion" { return .gameEvent(message, root: .parallel([.sfx(clip: "destruction.wav", completion: .wait), speech])) }
        return .gameEvent(message, root: speech)
    }

    private static func cityDonated(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let from = int(p["from_player_id"]), let to = int(p["to_player_id"]), let city = int(p["city_id"]) else { return nil }
        let message = "\(KoreanPresentationText.subject(c.playerName(from))) \(KoreanPresentationText.object(c.cityName(city))) \(c.playerName(to))에게 기부했습니다"
        if c.isLocal(to) { return .gameEvent(message, root: .sequence([.voice(clip: "nice.wav", fallbackTTS: nil), .tts(message)])) }
        return .gameEvent(message)
    }

    private static func cityChanged(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let a = int(p["player_a_id"]), let b = int(p["player_b_id"]), let ca = int(p["city_a_id"]), let cb = int(p["city_b_id"]) else { return nil }
        let message = "\(KoreanPresentationText.subject(c.playerName(a))) 자신의 \(KoreanPresentationText.conjunction(c.cityName(ca))) \(c.playerName(b))의 \(KoreanPresentationText.object(c.cityName(cb))) 교환했습니다"
        if c.isLocal(b) { return .gameEvent(message, root: .sequence([.voice(clip: "oh_no.wav", fallbackTTS: nil), .tts(message)])) }
        return .gameEvent(message)
    }

    private static func cityForceSold(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let attacker = int(p["attacker_player_id"]), let owner = int(p["owner_player_id"]), let city = int(p["city_id"]) else { return nil }
        let attackerName = c.playerName(attacker)
        let ownerName = c.playerName(owner)
        let resultSubject = c.isLocal(owner) ? "" : "\(KoreanPresentationText.subject(ownerName)) "
        let message = "\(KoreanPresentationText.subject(attackerName)) \(ownerName)의 \(KoreanPresentationText.object(c.cityName(city))) 강제 매각했습니다. \(resultSubject)매각 대금으로 \(KoreanPresentationText.object(KoreanPresentationText.marble(int(p["sell_value"])))) 받았습니다"
        if c.isLocal(owner) { return .gameEvent(message, root: .sequence([.voice(clip: "oh_no.wav", fallbackTTS: nil), .tts(message)])) }
        return .gameEvent(message)
    }

    private static func attackDefended(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let attacker = int(p["attacker_player_id"]), let defender = int(p["defender_player_id"]) else { return nil }
        let attackType = (p["attack_type"] as? String) ?? ""
        let defenseType = (p["defense_card_type"] as? String) ?? ""
        let attackLabel = ["city_change":"도시 체인지", "forced_sell":"강제 매각", "yellow_dust":"황사", "blackout":"도시 정전", "plague":"전염병", "alien_invasion":"외계인 침공", "earthquake":"지진"][attackType] ?? attackType
        let defenseLabel = ["angel":"천사", "shield":"방패"][defenseType] ?? defenseType
        let targetIDs = ints(p["target_city_ids"])
        let message: String
        if !targetIDs.isEmpty {
            let cities = targetIDs.map { c.cityName($0) }.joined(separator: ", ")
            message = "\(KoreanPresentationText.subject(c.playerName(defender))) \(defenseLabel) 카드로 \(c.playerName(attacker))의 \(attackLabel) 공격에서 \(cities)를 보호했습니다"
        } else {
            message = "\(KoreanPresentationText.subject(c.playerName(defender))) \(defenseLabel) 카드로 \(c.playerName(attacker))의 \(attackLabel) 공격을 막았습니다"
        }
        return .gameEvent(message, root: .sequence([.voice(clip: "use_defence_card.wav", fallbackTTS: nil), .tts(message)]))
    }

    private static func sponsorshipPaid(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let payer = int(p["payer_player_id"]), let receiver = int(p["receiver_player_id"]), c.isLocal(payer) else { return nil }
        return .gameEvent("후원금으로 \(c.playerName(receiver))에게 10만 마블을 주었습니다.")
    }

    private static func sponsorshipReceived(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let receiver = int(p["receiver_player_id"]), c.isLocal(receiver) else { return nil }
        let amount = int(p["total_amount"]) ?? 0
        return .gameEvent(amount <= 0 ? "받을 수 있는 후원금이 없습니다." : "후원금으로 모두에게서 10만 마블씩 받았습니다.")
    }

    private static func cityEffectActivated(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let cityID = int(p["city_id"]) else { return nil }
        let effect = (p["effect_type"] as? String) ?? ""
        let causerID = int(p["caused_by_player_id"])
        let causer = c.playerName(causerID)
        let batchCityIDs = ints(p["effect_batch_city_ids"])

        // client(393): 전염병의 여러 도시 적용도 첫 알림 한 번으로 묶는다.
        if effect == "plague", !batchCityIDs.isEmpty {
            guard bool(p["effect_batch_primary"]) == true else { return nil }
            let cities = batchCityIDs.map { c.cityName($0) }.joined(separator: ", ")
            let message = "\(causer)의 전염병 공격으로 \(cities) 통행료 50퍼센트 하락"
            let isMine = causerID != c.localPlayerID && batchCityIDs.contains { c.ownerID(of: $0) == c.localPlayerID }
            let speech: PresentationNode = isMine
                ? .sequence([.voice(clip: "oh_no.wav", fallbackTTS: nil), .tts(message)])
                : .tts(message)
            return .gameEvent(message, root: speech)
        }

        let city = c.cityName(cityID)
        let message: String
        switch effect {
        case "yellow_dust": message = "\(causer)의 황사 공격으로 \(city) 통행료 50퍼센트 하락"
        case "blackout": message = "\(causer)의 도시 정전 공격으로 \(city) 통행료 무료"
        case "plague": message = "\(causer)의 전염병 공격으로 \(city) 통행료 50퍼센트 하락"
        default: message = "\(city)에 \(effectLabel(effect)) 효과가 적용됐습니다."
        }
        let isAttack = effect == "yellow_dust" || effect == "blackout" || effect == "plague"
        let isMine = isAttack && c.ownerID(of: cityID) == c.localPlayerID && causerID != c.localPlayerID
        let speech: PresentationNode = isMine ? .sequence([.voice(clip: "oh_no.wav", fallbackTTS: nil), .tts(message)]) : .tts(message)
        if effect == "yellow_dust" { return .gameEvent(message, root: .parallel([.sfx(clip: "yellow_dust.wav", completion: .wait), speech])) }
        return .gameEvent(message, root: speech)
    }

    private static func cityEffectReleased(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let cityID = int(p["city_id"]) else { return nil }
        let effect = (p["effect_type"] as? String) ?? ""
        let batchCityIDs = ints(p["effect_batch_city_ids"])
        if effect == "plague", !batchCityIDs.isEmpty {
            guard bool(p["effect_batch_primary"]) == true else { return nil }
            let cities = batchCityIDs.map { c.cityName($0) }.joined(separator: ", ")
            return .gameEvent("\(cities)의 \(effectLabel(effect)) 해제")
        }
        return .gameEvent("\(c.cityName(cityID))의 \(effectLabel(effect)) 해제")
    }

    private static func tollDefended(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), let cityID = int(p["city_id"]) else { return nil }
        let original = KoreanPresentationText.marble(int(p["original_amount"]))
        let final = KoreanPresentationText.marble(int(p["final_amount"]))
        let defense = (p["defense_card_type"] as? String) ?? ""
        let label = ["angel":"천사", "discount_coupon":"할인 쿠폰"][defense] ?? defense
        let message = (bool(p["is_fully_defended"]) ?? false)
            ? "\(KoreanPresentationText.subject(c.playerName(playerID))) \(label) 카드로 \(c.cityName(cityID)) 통행료 \(KoreanPresentationText.object(original)) 전액 방어했습니다"
            : "\(KoreanPresentationText.subject(c.playerName(playerID))) \(KoreanPresentationText.object(label)) 사용하여 \(c.cityName(cityID)) 통행료가 \(original)에서 \(final)이 되었습니다"
        return .gameEvent(message)
    }

    private static func islandBuildingUpdated(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        touristUpdate(cityIDs: ints(p["city_ids"]), building: p["new_building_type"] as? String, context: c)
    }

    private static func beachBuildingUpdated(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let cityID = int(p["city_id"]) else { return nil }
        return touristUpdate(cityIDs: [cityID], building: p["new_building_type"] as? String, context: c)
    }

    private static func touristUpdate(cityIDs: [Int], building: String?, context c: GamePresentationContext) -> PresentationPlan? {
        guard let building, !building.isEmpty, !cityIDs.isEmpty else { return nil }
        let names = cityIDs.map { c.cityName($0) }.joined(separator: ", ")
        if building == "깃발" { return .gameEvent("\(names) 깃발 설치") }
        if building == "파라솔" || building == "방갈로" { return .gameEvent("\(names) \(building)로 업데이트") }
        return nil
    }

    private static func salaryPaid(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), c.isLocal(playerID) else { return nil }
        let amount = KoreanPresentationText.marble(int(p["amount"]))
        return .gameEvent((bool(p["is_doubled"]) ?? false) ? "월급 2배 \(amount) 수령" : "월급 \(amount) 수령")
    }

    private static func taxPaid(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]) else { return nil }
        let suffix = ints(p["sold_city_ids"]).isEmpty ? "" : " 도시 \(ints(p["sold_city_ids"]).count)곳 매각"
        let prefix = c.isLocal(playerID) ? "" : "\(c.playerName(playerID)) "
        let message = "\(prefix)세금 \(KoreanPresentationText.marble(int(p["amount"]))) 납부\(suffix)"
        if c.isLocal(playerID) { return .gameEvent(message, root: .parallel([.sfx(clip: "money_out.wav", completion: .wait), .tts(message)])) }
        return .gameEvent(message)
    }

    private static func playerBankrupt(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]) else { return nil }
        let creditorID = int(p["creditor_id"])
        let paid = int(p["paid_amount"]) ?? 0
        let message = creditorID.map { "\(c.playerName(playerID)) 파산. \(c.playerName($0))에게 \(KoreanPresentationText.marble(paid)) 지불" } ?? "\(c.playerName(playerID)) 파산"
        if c.isLocal(playerID) { return .gameEvent(message, root: .parallel([.sfx(clip: "losing.wav", completion: .wait), .tts(message)])) }
        if creditorID == c.localPlayerID && paid > 0 { return .gameEvent(message, root: .parallel([.sfx(clip: "money_in.wav", completion: .wait), .tts(message)])) }
        return .gameEvent(message)
    }

    private static func colorMonopoly(_ p: [String: Any], _ c: GamePresentationContext, achieved: Bool) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), let group = p["group"] as? String, !group.isEmpty else { return nil }
        return .gameEvent("\(c.playerName(playerID)) \(group) 컬러 독점 \(achieved ? "달성" : "해제")")
    }

    private static func gameOver(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        let winnerID = int(p["winner_player_id"])
        var message = winnerID.map { "\(c.playerName($0)) 승리" } ?? "승리"
        var labels: [String] = []
        if let achievements = p["achievements"] as? [[String: Any]] {
            for item in achievements {
                switch item["ending_monopoly_type"] as? String {
                case "triple_color": labels.append("트리플 컬러독점")
                case "tourist": labels.append("관광지독점")
                case "line":
                    if let line = item["line_type"] as? String, !line.isEmpty { labels.append("\(line.uppercased())라인독점") }
                default: break
                }
            }
        }
        let achievementLabels = labels
        if labels.isEmpty, bool(p["is_last_survivor"]) == true { labels.append("최후의 1인") }
        if !labels.isEmpty { message += ": \(labels.joined(separator: "/"))" }
        // client(393): 최후의 1인 패배는 파산 시 losing.wav가 이미 재생되므로
        // game_over에서 중복하지 않는다. 엔딩 독점 패배에만 이 SFX를 쓴다.
        let sfx: String? = winnerID == c.localPlayerID ? "winning.wav" : (!achievementLabels.isEmpty ? "losing.wav" : nil)
        var nodes: [PresentationNode] = [.bgmStop]
        if let sfx { nodes.append(.sfx(clip: sfx, completion: .wait)) }
        nodes.append(.tts(message))
        return .gameEvent(message, root: .parallel(nodes))
    }

    private static func turnStarted(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), c.players.contains(where: { $0.playerID == playerID }) else { return nil }
        let message = "\(c.playerName(playerID)) 차례"
        let speech: PresentationNode = c.isLocal(playerID) ? .voice(clip: "my_turn.wav", fallbackTTS: message) : .tts(message)
        return .gameEvent(message, root: .parallel([.sfx(clip: "turn_end.wav", completion: .wait), speech]))
    }

    private static func worldTravelStarted(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]) else { return nil }
        let cost = int(p["cost"]) ?? 0
        let message: String
        if cost > 0 { message = c.isLocal(playerID) ? "세계여행 비용 \(KoreanPresentationText.marble(cost)) 지불" : "\(c.playerName(playerID)) 세계여행 비용 \(KoreanPresentationText.marble(cost)) 지불" }
        else { message = c.isLocal(playerID) ? "무료 세계여행을 시작했습니다." : "\(KoreanPresentationText.subject(c.playerName(playerID))) 무료 세계여행을 시작했습니다." }
        if c.isLocal(playerID) { return .gameEvent(message, root: .sequence([.tts(message), .tts("다음 턴에 목적지로 이동하세요.")])) }
        return .gameEvent(message)
    }

    private static func strandedRollFailed(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]) else { return nil }
        let d1 = int(p["die1"]) ?? 0, d2 = int(p["die2"]) ?? 0, turns = int(p["turns_remaining"]) ?? 0
        let remain = turns > 0 ? "잔여 \(turns)턴" : "잔여 턴 없음"
        let result = c.isLocal(playerID) ? "탈출 실패. \(remain)." : "\(c.playerName(playerID)) 탈출 실패. \(remain)."
        let message = "[\(c.playerName(playerID))] \(d1 + d2) 탈출 실패. \(remain)"
        var nodes: [PresentationNode] = [.sfx(clip: "dice_roll.wav", completion: .wait)]
        nodes.append(contentsOf: diceVoiceNodes(die1: d1, die2: d2, isDouble: d1 == d2, playerName: c.playerName(playerID)))
        nodes.append(.tts(result))
        return .gameEvent(message, root: .sequence(nodes))
    }

    private static func playerStranded(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]) else { return nil }
        let message = c.isLocal(playerID)
            ? "무인도에 갇혔습니다. 3턴 안에 더블이나 보석금(H) 또는 탈출 카드(Y)로 탈출할 수 있습니다."
            : "\(KoreanPresentationText.subject(c.playerName(playerID))) 무인도에 갇혔습니다."
        return .gameEvent(message)
    }

    private static func olympicHosted(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), let cityID = int(p["city_id"]) else { return nil }
        let actor = c.isLocal(playerID) ? "당신이" : KoreanPresentationText.subject(c.playerName(playerID))
        return .gameEvent("\(actor) \(c.cityName(cityID))에 올림픽 \(int(p["olympic_count"]) ?? 1)회 개최")
    }

    private static func bonusChallenge(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]) else { return nil }
        let actor = c.isLocal(playerID) ? "당신" : c.playerName(playerID), step = int(p["step"]) ?? 1
        let message = step <= 1 ? "\(actor) 보너스 게임 도전" : "\(actor) 보너스 게임 \(step)차 도전"
        return .gameEvent(message, root: .parallel([.sfx(clip: "coin_drop.wav", completion: .wait), .tts(message)]))
    }

    private static func bonusResult(_ p: [String: Any]) -> PresentationPlan? {
        let success = bool(p["success"]) ?? false, step = int(p["step"]) ?? 0
        let message = success ? "성공" : "실패"
        let voice = success ? (step >= 3 ? "jackpot.wav" : "success.wav") : "fail.wav"
        return .gameEvent(message, root: .voice(clip: voice, fallbackTTS: message))
    }

    private static func bonusReward(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]), let reward = int(p["reward"]), reward > 0 else { return nil }
        let message = "축하합니다!! 보상금은 \(KoreanPresentationText.marble(reward))입니다."
        if c.isLocal(playerID) { return .gameEvent(message, root: .parallel([.sfx(clip: "money_in.wav", completion: .wait), .tts(message)])) }
        return .gameEvent(message)
    }

    private static func bonusRefund(_ p: [String: Any]) -> PresentationPlan? {
        guard let amount = int(p["amount"]), amount > 0 else { return nil }
        return .gameEvent("도전비 \(KoreanPresentationText.marble(amount)) 환급")
    }

    private static func cardHeld(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let card = p["card_name"] as? String, !card.isEmpty else { return nil }
        let playerID = int(p["player_id"])
        let prefix = playerID.map { c.isLocal($0) ? "" : "\(c.playerName($0)) " } ?? ""
        return .gameEvent("\(prefix)\(card) 카드를 보관했습니다.")
    }

    private static func bailSelection(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        var message = (bool(p["selected"]) ?? false) ? "보석금 지불 선택" : "보석금 지불 해제"
        if let playerID = int(p["player_id"]), !c.isLocal(playerID) { message = "\(c.playerName(playerID)) \(message)" }
        return .systemTTS(message, queuePolicy: .interrupt, persistentNotice: message)
    }

    private static func heldCardSelection(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        let card = (p["card_name"] as? String) ?? "", selected = bool(p["selected"]) ?? false
        var message = selected ? (card.isEmpty ? "보관 카드 사용 선택" : "\(card) 사용 선택") : (card.isEmpty ? "보관 카드 사용 해제" : "\(card) 사용 해제")
        if let playerID = int(p["player_id"]), !c.isLocal(playerID) { message = "\(c.playerName(playerID)) \(message)" }
        return .systemTTS(message, queuePolicy: .interrupt, persistentNotice: message)
    }

    private static func bailPaid(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let playerID = int(p["player_id"]) else { return nil }
        let prefix = c.isLocal(playerID) ? "" : "\(c.playerName(playerID)) "
        return .gameEvent("\(prefix)보석금 \(KoreanPresentationText.marble(int(p["amount"]))) 지불")
    }

    private static func playerEffect(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        var message = (p["effect_type"] as? String) == "salary_booster" ? "월급 부스터 활성화. 다음 출발지 통과 월급이 2배입니다." : "플레이어 효과가 활성화됐습니다."
        if let playerID = int(p["player_id"]), !c.isLocal(playerID) { message = "\(c.playerName(playerID)) \(message)" }
        return .systemTTS(message, queuePolicy: .interrupt, persistentNotice: message)
    }

    private static func interruptReason(_ p: [String: Any], _ c: GamePresentationContext, key: String) -> PresentationPlan? {
        let code = ((p[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var message: String
        if code.isEmpty {
            message = key == "reason_code" ? "주사위를 굴릴 수 없습니다." : "알 수 없는 오류가 발생했습니다."
        } else {
            message = reasonText(code)
        }
        if let playerID = int(p["player_id"]), !c.isLocal(playerID) { message = "\(c.playerName(playerID)) \(message)" }
        return .systemTTS(message, queuePolicy: .interrupt, persistentNotice: key == "reason_code" ? message : nil)
    }

    private static func interactionPresentation(_ p: [String: Any], _ c: GamePresentationContext) -> PresentationPlan? {
        guard let semantic = p["payload"] as? [String: Any] else { return nil }
        let mission = (semantic["mission_type"] as? String) ?? ""
        let interactionType = (p["interaction_type"] as? String) ?? ""

        if mission == "fortune_card", interactionType == "acknowledge" {
            let cardID = ((semantic["card_id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let reaction = fortuneReaction(cardID: cardID, payload: semantic, context: c)
            var nodes: [PresentationNode] = [.sfx(clip: "card_sellection.wav", completion: .wait)]
            if let reaction { nodes.append(.voice(clip: reaction, fallbackTTS: nil)) }
            return PresentationPlan(
                root: nodes.count == 1 ? nodes[0] : .parallel(nodes),
                category: .gameplay,
                queuePolicy: .enqueue,
                interruptRetention: .preservePending
            )
        }

        if mission == "fortune_selection" {
            let groups = semantic["groups"] as? [[String: Any]] ?? []
            let roles = Set(groups.compactMap { $0["role"] as? String })
            if roles.contains("attack_city") || roles.contains("opponent_city") {
                return PresentationPlan(
                    root: .voice(clip: "attack_area.wav", fallbackTTS: nil),
                    category: .gameplay,
                    queuePolicy: .enqueue,
                    interruptRetention: .preservePending
                )
            }
        }

        if mission == "defense" {
            return PresentationPlan(
                root: .voice(clip: "defence_card.wav", fallbackTTS: nil),
                category: .gameplay,
                queuePolicy: .enqueue,
                interruptRetention: .preservePending
            )
        }
        return nil
    }

    private static func interactionPresentationActivated(_ p: [String: Any]) -> PresentationPlan? {
        guard p["action_type"] as? String == "world_travel_destination" else { return nil }
        let prompt = "목적지를 선택하고 엔터를 누르세요."
        if bool(p["first_activation"]) == true {
            return PresentationPlan(
                root: .sequence([
                    .parallel([
                        .voice(clip: "select_area.wav", fallbackTTS: nil),
                        .bgmPlay(clip: "airplane.mp3", loop: true)
                    ]),
                    .tts(prompt)
                ]),
                category: .gameplay,
                queuePolicy: .enqueue,
                interruptRetention: .preservePending
            )
        }
        return PresentationPlan(
            root: .sequence([
                .voice(clip: "select_area.wav", fallbackTTS: nil),
                .tts(prompt)
            ]),
            category: .gameplay,
            queuePolicy: .enqueue,
            interruptRetention: .preservePending
        )
    }

    private static func fortuneReaction(cardID: String, payload: [String: Any], context c: GamePresentationContext) -> String? {
        let stateDependent: Set<String> = [
            "olympic_host", "move_olympic", "city_change_1", "city_change_2",
            "city_donate_1", "city_donate_2", "forced_sell", "alien_invasion",
            "earthquake", "yellow_dust", "blackout", "plague"
        ]
        if stateDependent.contains(cardID), payload.keys.contains("effect_applicable") {
            guard let applicable = bool(payload["effect_applicable"]), applicable else { return nil }
        }
        if cardID == "move_olympic", payload.keys.contains("effect_applicable") {
            guard let ownerID = int(payload["effect_target_owner_id"]), c.localPlayerID != nil else { return nil }
            return ownerID == c.localPlayerID ? "nice.wav" : "oh_no.wav"
        }
        let nice: Set<String> = [
            "angel_1", "angel_2", "shield_1", "shield_2", "discount_coupon_1", "discount_coupon_2",
            "salary_booster", "island_escape", "move_start", "move_bonus", "sponsorship", "olympic_host",
            "move_world_travel", "city_change_1", "city_change_2", "forced_sell", "alien_invasion",
            "earthquake", "yellow_dust", "blackout", "plague"
        ]
        if nice.contains(cardID) { return "nice.wav" }
        if cardID == "move_tax_1" || cardID == "move_tax_2" { return "ah.wav" }
        if cardID == "city_donate_1" || cardID == "city_donate_2" { return "oh_no.wav" }
        if cardID == "move_island" { return "aigo.wav" }
        return nil
    }

    private static func diceVoiceNodes(die1: Int, die2: Int, isDouble: Bool, playerName: String) -> [PresentationNode] {
        let total = die1 + die2
        if isDouble {
            return [.voice(clip: "double.wav", fallbackTTS: "[\(playerName)] 더블 \(total)"), .voice(clip: "dice_\(total).wav", fallbackTTS: nil)]
        }
        return [.voice(clip: "dice_\(total).wav", fallbackTTS: "[\(playerName)] \(total)")]
    }

    private static func effectLabel(_ code: String) -> String {
        ["yellow_dust":"황사", "blackout":"도시 정전", "plague":"전염병"][code] ?? code
    }

    private static func reasonText(_ code: String) -> String {
        switch code {
        case "not_enough_marble": return "마블이 부족합니다."
        case "not_enough_asset": return "매각 가능한 자산이 부족합니다."
        case "already_owned": return "이미 소유자가 있습니다."
        case "not_owner": return "소유자가 아닙니다."
        case "max_building": return "이미 최대 단계입니다."
        case "landmark_not_acquirable": return "랜드마크 도시는 인수할 수 없습니다."
        case "island_not_acquirable": return "섬 도시는 인수할 수 없습니다."
        case "beach_not_acquirable": return "해변 도시는 인수할 수 없습니다."
        case "invalid_selection": return "선택할 수 없는 항목입니다."
        case "invalid_action": return "잘못된 동작입니다."
        case "invalid_state": return "현재 상태에서는 처리할 수 없습니다."
        case "not_my_turn": return "내 차례가 아닙니다."
        case "already_started": return "이미 시작했습니다."
        case "not_started": return "게임이 아직 시작되지 않았습니다."
        case "turn_timeout", "timeout": return "제한 시간이 지났습니다."
        case "cannot_cancel": return "취소할 수 없습니다."
        case "max_olympic": return "이미 최대 올림픽 개최 상태입니다."
        case "not_implemented": return "아직 구현되지 않은 기능입니다."
        case "unknown_error": return "알 수 없는 오류가 발생했습니다."
        case "card_not_found": return "사용할 수 있는 카드가 없습니다."
        case "card_not_usable": return "지금 사용할 수 없는 카드입니다."
        case "turn_preparation_unavailable": return "현재는 주사위 실행 준비를 변경할 수 없습니다."
        case "not_stranded": return "무인도 상태가 아닙니다."
        case "bail_marble_shortage": return "보석금 20만 마블을 지급하기에 마블이 부족합니다."
        case "island_escape_not_available": return "무인도 탈출 카드는 무인도에서만 사용할 수 있습니다."
        case "salary_booster_already_active": return "월급 부스터가 이미 활성화되어 있습니다."
        case "held_card_selection_stale": return "선택했던 보관 카드가 현재 보관 카드와 일치하지 않습니다."
        case "turn_preparation_conflict": return "보석금과 무인도 탈출 카드를 동시에 사용할 수 없습니다."
        case "city_not_found": return "도시 정보를 찾을 수 없습니다."
        case "player_not_found": return "플레이어 정보를 찾을 수 없습니다."
        default: return code
        }
    }

    private static func int(_ value: Any?) -> Int? { WireScalarParser.exactInt(value) }
    private static func bool(_ value: Any?) -> Bool? { WireScalarParser.exactBool(value) }
    private static func ints(_ value: Any?) -> [Int] { (value as? [Any])?.compactMap(WireScalarParser.exactInt) ?? [] }
    private static func strings(_ value: Any?) -> [String] { (value as? [Any])?.compactMap { $0 as? String }.filter { !$0.isEmpty } ?? [] }
}
