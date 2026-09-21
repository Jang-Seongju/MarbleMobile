# MarbleMobile 1차 작업본 — 검증 보완본

기준: server(677) / client(393)

## 1차 범위
- 회원가입
- 로그인
- `아이디/비밀번호 저장`: 아이디/선택 여부는 UserDefaults, 비밀번호는 Keychain
- 로그인 Magic Tap
- HTTP 인증 후 동일 access token으로 WebSocket `/ws?token=...` 연결
- strict `session_entry` 판정 후 `normal_lobby`에서 로비 활성화
- PC판과 같은 접속자/방 목록 표시 문구
- 접속자 목록 / 게임방 목록 하단 전환 버튼
- `accessibilityScrollAction` 기반 세 손가락 좌/우 목록 전환 후보
- 접속자/방 row에 PC 팝업 메뉴와 같은 순서의 Custom Actions 모델
- 친구/차단 관계 상태에 따른 action 조건
- 친구 해제/차단 확인
- PC formatter와 같은 방 정보/사용자 정보 출력
- profile 보호 API access-token refresh 1회 재시도
- WebSocket generation 격리

## PC와 다른 플랫폼 구현
- wxPython UI -> SwiftUI
- Windows Credential Manager -> iOS Keychain
- PC 팝업 메뉴 -> VoiceOver Custom Actions
- PC Alt 메뉴 전체는 후속 전역 메뉴 화면으로 이식 예정

## 의도적으로 2차 이후로 남긴 경계
게임방 UI가 없는 상태에서 서버 membership을 실제로 바꾸면 클라이언트와 서버 상태가 갈라질 수 있으므로 `방 개설/참여/관중석 입장`은 1차에서 메뉴 구조만 유지하고 실행은 활성화하지 않는다. 게임방 초대도 현재 `hasGameRoom=false`라 비활성이다.

PC의 메시지 창/쪽지함도 별도 화면이므로 2차에 완전 이식한다. 해당 Custom Action 위치는 유지하되 1차에서 임시 축약 UI를 만들지 않는다.

`ACTIVE_GAME_RECOVERY`가 오면 정상 로비를 활성화하지 않고 strict recovery entry를 보존한 채 복구 필요 상태로 둔다. 실제 복구 UI는 게임 UI 단계에서 연결한다.

## 서버 주소
`iOS/MarbleMobile/Info.plist`의 `MARBLE_BASE_URL`은 현재 `http://127.0.0.1:8000`이다. 실제 iPhone에서 127.0.0.1은 iPhone 자신이므로 실기기 빌드 전 반드시 iPhone에서 접근 가능한 서버 origin으로 변경해야 한다.

## 검증
자세한 내용은 `PHASE1_VERIFICATION_REPORT.md` 참조.

- `swift test`: 12 tests / 0 failures
- iOS Swift source parse: PASS
- Info.plist / project.yml / GitHub Actions YAML parse: PASS
- Xcode/UIKit/SwiftUI 실제 compile: 아직 미검증 (macOS CI 필요)
