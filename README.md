# MarbleMobile 1차 구현본

기준: server(677) / client(393)

## 1차 범위
- 회원가입
- 로그인
- `아이디/비밀번호 저장` 정책: 아이디/선택 여부는 UserDefaults, 비밀번호는 Keychain
- 로그인 Magic Tap
- HTTP 인증 후 동일 access token으로 WebSocket `/ws?token=...` 연결
- `session_entry == normal_lobby` 이후 로비 활성화
- PC판과 같은 접속자 표시 문구 및 방 목록 표시 문구
- 접속자 목록 / 게임방 목록 하단 전환 버튼
- VoiceOver accessibility scroll action으로 세 손가락 좌/우 전환 경로 제공
- 접속자/방 row에 PC 팝업 메뉴와 같은 순서의 Custom Actions 모델 제공
- 사회관계 상태에 따른 친구/차단 액션 조건을 client(393)과 동일하게 계산
- 방 정보는 현재 room_list metadata로 조회 가능

## 의도적으로 2차 이후로 남긴 경계
게임방 UI가 없는 상태에서 서버 membership을 실제로 바꾸면 클라이언트와 서버 상태가 갈라질 수 있으므로 `방 개설/참여/관중석 입장`은 1차에서 표시 구조만 유지하고 실행은 활성화하지 않는다. 같은 이유로 게임방 초대도 현재 `hasGameRoom=false`라 비활성이다.

PC의 메시지 창/쪽지함 전체 UI도 대기실 본체와 별도 화면이므로 2차에 완전 이식한다. 현재 액션 모델/프로토콜 경계는 만들어 두었지만 해당 화면을 임시 축약판으로 만들지 않는다.

`ACTIVE_GAME_RECOVERY`가 오면 로비를 정상 활성화하지 않고 복구 필요 상태로 남긴다. 게임 복구 UI를 임시로 흉내내지 않는다.

## 서버 주소
`iOS/MarbleMobile/Info.plist`의 `MARBLE_BASE_URL`은 현재 PC 로컬 기준값 `http://127.0.0.1:8000`이다. 실제 iPhone에서는 127.0.0.1이 iPhone 자신이므로, 실기기 빌드 전에 iPhone에서 접근 가능한 서버 주소로 바꿔야 한다.

## Windows/Linux에서 가능한 검증
순수 공통 코어는 Swift Package로 분리했다.

```bash
swift test
```

실제 SwiftUI/UIKit 컴파일은 macOS/Xcode가 필요하므로 `.github/workflows/ios-compile.yml`이 XcodeGen으로 프로젝트를 생성하고 iOS Simulator용 무서명 빌드를 수행한다.
