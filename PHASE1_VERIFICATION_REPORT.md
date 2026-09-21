# MarbleMobile 1차 검증 보고서

기준일: 2026-09-20

## 기준본
- 서버: `server(677)`
- PC 클라이언트: `client(393)`
- 검증 대상: 최초 `MarbleMobilePhase1` 1차 작업본

## 검증 방법
실제 `server(677)` / `client(393)` 압축본을 풀어 다음 구현을 파일 단위로 대조했다.

- PC 로그인/저장: `app/ui/login_window.py`, `app/network/http_client.py`
- PC 회원가입: `app/ui/register_window.py`
- PC 로비/팝업 메뉴: `app/ui/lobby_window.py`
- PC 사회기능 wire 계약: `app/social/protocol.py`
- PC session entry: `app/network/session_entry.py`
- PC 사용자 정보 formatter: `app/presentation/user_profile.py`, `app/presentation/datetime_text.py`
- PC 방 정보 formatter: `app/presentation/room_info.py`
- 서버 인증/refresh: `app/api/routes/auth.py`, `app/api/deps.py`
- 서버 사용자 profile: `app/api/routes/user.py`, `app/schemas/user_profile.py`
- 서버 social handler 및 invitation handler
- 서버 `user_list`, `room_list` wire payload

## 최초 작업본에서 발견되어 수정한 항목

### 1. 회원가입 왕복 시 로그인 입력 상태가 사라질 수 있음
최초본은 `login -> register -> login`을 Root 화면 자체 교체로 구현하여 PC판과 달리 로그인 창 상태가 재생성될 수 있었다.

수정:
- 회원가입을 LoginView의 sheet로 분리.
- 로그인 입력값/저장 체크 상태는 AppModel에 보존.
- 회원가입 완료/취소 뒤 로그인 아이디 입력으로 VoiceOver 포커스 복귀.
- 연결 종료 후 로그인 복귀 시에도 현재 아이디/비밀번호/저장 체크 상태를 다시 저장정보로 덮어쓰지 않음.

### 2. 아이디 변경 시 비밀번호 초기화 계약 보완
PC판은 아이디가 바뀌면 현재 비밀번호 입력을 항상 지운다.

수정:
- iOS도 사용자에 의한 아이디 변경 시 현재 비밀번호를 즉시 지움.

### 3. Keychain 이전 계정 비밀번호 잔존 가능성 제거
최초본은 저장 계정 A에서 계정 B로 변경하거나 저장 해제할 때 A의 Keychain 항목이 남을 수 있었다.

수정:
- 저장 계정 변경 시 이전 계정 Keychain 항목 삭제.
- 저장 해제 시 저장돼 있던 계정과 현재 계정의 관련 Keychain 항목 정리.

### 4. `session_entry` 검증이 PC보다 느슨함
최초본은 `entry_mode == normal_lobby` 여부만 보아 잘못된 recovery payload나 누락 필드를 허용할 수 있었다.

수정:
- PC `parse_session_entry()`와 같은 strict parser 추가.
- `normal_lobby`에 recovery 필드가 있으면 오류.
- `active_game_recovery`는 recovery_id / room_id / game_session_id / your_player_id를 모두 엄격 검증.
- 잘못된 응답이면 WebSocket을 정리하고 로그인으로 복귀하며 PC와 동일한 오류 문구를 사용.

### 5. 사용자 정보 출력이 PC formatter와 다름
최초본은 profile 응답을 top-level nickname/username으로 잘못 읽고 축약 출력했다. 서버 응답은 account/stats/ranking/runtime 중첩 구조다.

수정:
- PC `build_user_profile_text()`를 Swift 공통 formatter로 포팅.
- 계정 정보 / 현재 상태 / 기본 전적 / 승리 유형 / 누적 점수 / 보정 평균 / 순위 평가 섹션과 표시 형식을 유지.
- 날짜, 마블 천 단위, 승점, 퍼센트, 6자리 보정값, 순위, 랭킹 제외 사유 형식을 PC와 일치시킴.

### 6. 방 정보 출력이 PC formatter와 다름
최초본은 방 정보를 축약 문장으로 새로 만들었다.

수정:
- PC `build_room_info_text()`와 같은 줄/순서로 출력.
- 로비 metadata만 있는 경우 `참여 사용자: / 상세 정보 없음` 계약 유지.

### 7. 친구 해제/차단 확인 절차 누락
최초본은 Custom Action 실행 즉시 서버 명령을 보냈다.

수정:
- 친구 해제: `X님과의 친구 관계를 해제하시겠습니까?`
- 차단: `X님을 차단하시겠습니까?\n친구 관계와 대기 중인 친구 요청이 있으면 함께 정리됩니다.`
- 확인 뒤에만 wire 명령 전송.
- 차단 해제는 PC판처럼 별도 확인 없음.

### 8. 목록이 늦게 수신될 때 초기 VoiceOver 포커스 누락
최초본의 `.task`는 빈 목록 상태에서 먼저 실행될 수 있어, 이후 user_list가 와도 첫 사용자에 포커스가 가지 않을 수 있었다.

수정:
- user/room ID 배열 변화 감시.
- 현재 목록이 활성 상태이면 마지막 유효 포커스를 복원하고, 없으면 첫 항목에 포커스.
- normal_lobby 활성화 시 접속자 목록을 기본 페이지로 강제.

### 9. WebSocket 이전 세대 callback 격리 없음
이전 socket의 늦은 send/receive 오류가 새 연결에 영향을 줄 가능성이 있었다.

수정:
- WebSocket generation 추가.
- 현재 generation + 현재 socket이 일치하는 callback만 처리.

### 10. 보호 HTTP profile의 access token 만료 처리 누락
최초본은 사용자 정보 요청에서 access token이 만료되면 바로 실패했다.

수정:
- `access_token_expired`에서 `/auth/refresh` 1회 수행.
- 새 access/refresh token 쌍으로 원래 profile 요청 1회 재실행.
- refresh terminal failure / inactive_user는 로그인 복귀로 처리.
- 403/404/422 profile 오류 문구를 PC판과 맞춤.

### 11. BASE_URL 검증이 PC보다 느슨함
최초본은 API path/query/fragment가 들어간 BASE URL도 받을 수 있었다.

수정:
- PC 계약과 같이 http/https origin만 허용.
- path는 빈 값 또는 `/`만 허용하고 query/fragment는 거부.
- WebSocket URL은 정규화한 origin에서 `/ws`로 파생.

### 12. 사회기능 wire type을 UI 코드가 직접 작성
동작은 맞았지만 PC판의 `app/social/protocol.py`처럼 단일 원천이 아니었다.

수정:
- `WireMessages.swift` 추가.
- social_get_state / invitation_send / friend request / unfriend / block / unblock payload를 공통 builder로 이동.

## 확인된 PC parity
- 접속자 라벨 조립 순서: 나 -> 게임 중 -> 접속 상태.
- 방 목록 라벨: `방번호: 제목`, playing이면 `(게임 중)`.
- 사용자 팝업 메뉴 순서와 관계상태별 friend/block 항목.
- 방 팝업 메뉴 순서: 방 개설 / 참여하기 / 관중석 입장 / 방 정렬 / 방 정보.
- `social_state`, `user_list`, `room_list` 주요 payload key.
- `/ws?token=...` 연결 계약.
- 로그인/회원가입 HTTP endpoint와 중복확인 endpoint.

## 자동 검증 결과

### Swift Package 공통 코어
`swift test`

- 총 12 tests
- failures: 0

검증 항목:
- 사용자 presence 라벨
- 방 목록 라벨
- friend / blocked / incoming / outgoing 사용자 action 순서
- 자기 자신 action 조건
- 방 action 순서/활성 상태
- social payload parsing
- social wire message
- strict normal_lobby session_entry
- strict active_game_recovery session_entry
- PC 방 정보 formatter parity
- PC 사용자 정보 formatter parity

### iOS Swift 소스
`swiftc -frontend -parse iOS/MarbleMobile/*.swift`

- PASS

### 설정 파일
- `Info.plist`: plist parse PASS
- `project.yml`: YAML parse PASS
- GitHub Actions workflow: YAML parse PASS

## 현재 환경에서 검증할 수 없는 항목
Windows/Linux에는 Xcode/UIKit/SwiftUI iOS SDK가 없으므로 다음은 아직 **실제 통과를 주장하지 않는다**.

1. Xcode iOS type-check / simulator build
2. 실제 iPhone VoiceOver reading order
3. Custom Actions에서 한 손가락 위/아래 및 더블 탭 실동작
4. `accessibilityScrollAction`과 세 손가락 좌/우의 실제 방향/체감
5. Magic Tap 로그인
6. 실제 iPhone 로컬 네트워크/ATS 연결
7. Keychain 실기기 동작

이 항목은 macOS CI의 `xcodebuild`와 이후 실제 iPhone에서 검증해야 한다.

## 의도적으로 2차 이후에 남긴 기능
- 메시지 창
- 쪽지 작성/쪽지함
- 방 개설 UI
- 방 참가 UI
- 관중석 입장 UI
- 게임방 내부 UI
- ACTIVE_GAME_RECOVERY 실제 복구 화면
- PC Alt 전체 메뉴에 대응하는 iOS 전역 메뉴

따라서 1차의 방 개설/참여/관중석 및 메시지/쪽지 Custom Actions는 **메뉴 위치/조건 계약을 보존하지만, 목적 UI가 없으므로 활성 실행 대상으로 만들지 않는다.**

## 결론
최초 1차 작업본은 구조 방향은 맞았으나 그대로 첫 실기 후보로 승인하기에는 위 정합성 문제가 있었다. 본 검증에서 해당 문제를 수정했으며, 보완본은 Windows/Linux에서 가능한 공통 로직 및 구문 검증을 통과했다.

다음 승인 경계는 macOS CI에서 `xcodebuild`를 실제 통과시키는 것이다. 그 전까지는 `iOS compile verified`라고 부르지 않는다.
