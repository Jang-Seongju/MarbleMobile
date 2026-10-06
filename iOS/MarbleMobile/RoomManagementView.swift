import SwiftUI
import MarbleMobileCore

/// PC 방 관리의 명령과 서버 검증을 iOS Form으로 표시한다.
/// 참가자는 room_update.participants의 실제 방 소속 순서를 따른다.
struct RoomManagementView: View {
    private enum Visibility: String, CaseIterable, Identifiable {
        case publicRoom = "공개"
        case privateRoom = "비공개"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @State private var title = ""
    @State private var maxPlayers = 4
    @State private var visibility: Visibility = .publicRoom
    @State private var password = ""
    @State private var selectedUserID: Int?

    private var participants: [RoomTeamMember] {
        model.roomUpdate?.participants ?? []
    }

    private var kickCandidates: [RoomTeamMember] {
        participants.filter { $0.userID != model.session?.identity.userID }
    }

    private var request: RoomManagementRequest? {
        guard let update = model.roomUpdate else { return nil }
        return try? RoomManagementRequest(
            title: title, maxPlayers: maxPlayers,
            isPrivate: visibility == .privateRoom, password: password,
            currentCount: update.participants?.count, currentlyPrivate: update.isPrivate
        )
    }

    private var validationMessage: String? {
        guard let update = model.roomUpdate else { return nil }
        do {
            _ = try RoomManagementRequest(
                title: title, maxPlayers: maxPlayers,
                isPrivate: visibility == .privateRoom, password: password,
                currentCount: update.participants?.count, currentlyPrivate: update.isPrivate
            )
            return nil
        } catch { return error.localizedDescription }
    }

    private var canKickSelected: Bool {
        guard model.canManageRoom, let selectedUserID else { return false }
        return kickCandidates.contains(where: { $0.userID == selectedUserID })
            && !model.pendingRoomKickUserIDs.contains(selectedUserID)
            && !model.queuedRoomKickUserIDs.contains(selectedUserID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("참가자") {
                    if model.roomUpdate?.participants == nil {
                        Text("참가자 정보를 확인할 수 없습니다.")
                    } else if kickCandidates.isEmpty {
                        Text("퇴장할 참가자 없음")
                    } else {
                        ForEach(kickCandidates, id: \.userID) { participant in
                            Button {
                                selectedUserID = participant.userID
                            } label: {
                                HStack {
                                    Text(participant.nickname + (
                                        model.queuedRoomKickUserIDs.contains(participant.userID)
                                            ? " (게임 종료 후 퇴장 예정)" : ""
                                    ))
                                    Spacer()
                                    if selectedUserID == participant.userID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .accessibilityValue(selectedUserID == participant.userID ? "선택됨" : "")
                        }
                    }
                    Button("퇴장") {
                        if let selectedUserID { model.kickRoomParticipant(userID: selectedUserID) }
                    }
                    .disabled(!canKickSelected)
                }

                Section("방 제목") {
                    TextField("방 제목", text: $title)
                        .submitLabel(.done)
                }

                Section("참여 인원수 (2~4명)") {
                    Picker("참여 인원수", selection: $maxPlayers) {
                        ForEach(2...4, id: \.self) { count in
                            Text("\(count)명").tag(count)
                        }
                    }
                }

                Section("공개 설정") {
                    Picker("공개 설정", selection: $visibility) {
                        ForEach(Visibility.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .onChange(of: visibility) { _, value in
                        if value == .publicRoom { password = "" }
                    }
                }

                if visibility == .privateRoom {
                    Section("비밀번호 (변경하지 않으면 비워 두세요)") {
                        SecureField("비밀번호", text: $password)
                    }
                }

                Section {
                    Button("적용") {
                        if let request { model.updateRoomManagement(request) }
                    }
                    .disabled(!model.canManageRoom || request == nil)
                    Button("취소", role: .cancel) { model.isPresentingRoomManagement = false }
                } footer: {
                    if let validationMessage { Text(validationMessage) }
                }
            }
            .navigationTitle("방 관리")
            .onAppear {
                guard let update = model.roomUpdate else { return }
                title = update.title
                maxPlayers = update.maxPlayers
                visibility = update.isPrivate ? .privateRoom : .publicRoom
                selectedUserID = kickCandidates.first?.userID
            }
            .onChange(of: model.roomUpdate?.participants) { _, _ in
                if !kickCandidates.contains(where: { $0.userID == selectedUserID }) {
                    selectedUserID = kickCandidates.first?.userID
                }
            }
        }
    }
}
