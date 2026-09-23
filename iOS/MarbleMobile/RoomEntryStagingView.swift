import SwiftUI
import MarbleMobileCore

struct RoomEntryStagingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let room = model.roomEntry {
                    Text("방 생성 완료")
                        .font(.headline)
                    Text("방 제목: \(room.title)")
                    Text("참여 인원: 최대 \(room.maxPlayers)명")
                    Text("공개 여부: \(room.isPrivate ? "비공개" : "공개")")
                    Text("게임방 화면은 다음 단계에서 구현합니다.")
                } else {
                    Text("방 정보를 확인할 수 없습니다.")
                }
                Spacer()
                Button("로그아웃") { model.logout() }
            }
            .padding()
            .navigationTitle("게임방")
        }
    }
}
