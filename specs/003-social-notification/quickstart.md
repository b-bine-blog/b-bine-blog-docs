# 003 소셜·알림 확인 안내 (Quickstart)

**명세**: [spec.md](spec.md) | **API**: [contracts/social-api.yaml](contracts/social-api.yaml) | **데이터**: [data-model.md](data-model.md)

## 준비

- 자동 테스트: Docker가 돌고 있으면 `./gradlew test`(Testcontainers MySQL 8)로 전부 확인한다.
- 화면 확인: `local/start.sh`(Windows는 `local\start.bat`)로 MySQL·Mailpit·앱을 띄우고 http://localhost:8080 을 연다. 시드 계정은 모두 비밀번호 `Passw0rd!`이다.
  - `owner@local.test`: travel-log 블로그장
  - `member@local.test`: travel-log 멤버
  - `newbie@local.test`: 멤버 아님
  - `admin@local.test`: 메인 관리자
- 30초 확인을 눈으로 볼 때는 브라우저 개발자 도구의 네트워크 탭에서 `unread-count` 요청에 `X-User-Activity` 헤더가 없는지 함께 본다.

## 시나리오별 확인

| # | 확인할 것 | 방법 | 기대 결과 | 근거 |
|---|---|---|---|---|
| 1 | 알림함 | member로 로그인, 메인과 /blog/travel-log에서 종 아이콘 | 같은 사이드바, 탭 "전체"·댓글·좋아요·팔로우·구독·블로그·운영 | US1-1, FR-028 |
| 2 | 탭·더 보기 | 알림 25건(시드)으로 "전체" → 더 보기, "댓글" 탭 | 20건 → 25건, 댓글 탭은 댓글 알림만 | FR-029, D-102 #17 |
| 3 | 읽음 | 사이드바만 열기 → 알림 하나 누르기 → "모두 읽음" | 열기만으로는 그대로, 누른 것만 강조 색 없어짐, 그 탭 모두 읽음 | FR-030, D-102 #18 |
| 4 | 삭제 | x로 하나, "댓글" 탭 전체 삭제, "전체" 탭 전체 삭제 | 하나 → 그 탭만 → 모두 사라짐(확인 창 뒤) | FR-031, D-102 #19 |
| 5 | 30초 확인 | 화면을 둔 채 다른 계정으로 member 글에 댓글 | 30초 안에 배지 숫자 +1, 100건이면 "99+" | SC-001, D-102 #20 |
| 6 | 로그인 연장 제외 | 미체크 로그인으로 화면만 31분 둠(테스트는 MutableClock) | 로그아웃됨, 폴링 멈춤 | SC-012, D-62 |
| 7 | 이동 | 댓글·새 팔로워·폐쇄 예정·참여 신청·위임 요청·경고 알림 누르기 | 글·프로필·블로그·신청 목록 탭·블로그 홈(수락·거절)·내용만 | FR-033, D-102 #21 |
| 8 | 끌 수 없는 알림 | member가 9가지 모두 끈 뒤 owner가 폐쇄 버튼 → 철회 | 폐쇄 예정·철회 알림 옴, 설정 화면에 체크박스 없음 | US2-5, SC-003 |
| 9 | 폐쇄 알림 대상 | 폐쇄 버튼 뒤 newbie가 구독 → 3일 전(04:00 작업) | newbie도 3일 전부터 받음, 한 사람 한 번 | D-102 #22 |
| 10 | 프로필 | newbie로 owner 프로필, 개발자 도구 응답 | 닉네임·사진·소개·공개 블로그·팔로워 수, 이메일·이름·전화번호 없음 | US3, SC-010 |
| 11 | 소개 | member가 내 정보에서 소개 500자(줄바꿈 포함), 501자 | 저장·줄바꿈 보임 / 400 | D-102 #7 |
| 12 | 공개 범위 | owner의 비공개 블로그를 만들고 다른 계정·본인으로 프로필 | 다른 사람에게 안 보임, 본인에게 보임 | D-102 #6 |
| 13 | 팔로우 | newbie가 member 팔로우 → 취소 → 다시 팔로우 | 팔로워 수 1·0·1, 새 팔로워 알림은 1건 | US4, D-102 #3 |
| 14 | 자기 자신·관리자 | 내 프로필 팔로우 API, admin으로 팔로우·구독·신고 API | 400 SELF_NOT_ALLOWED / 403 ADMIN_NOT_ALLOWED | D-102 #1, D-90 |
| 15 | 요청 제한 | 팔로우 API 1분에 31번 | 31번째 429 RATE_LIMITED | D-102 #4 |
| 16 | 구독 | newbie가 travel-log 구독, owner가 자기 블로그 구독 | owner에게 구독 알림 / 400 | FR-040, D-102 #1 |
| 17 | 알림 설정 | "내 글 좋아요" 끄기 → 좋아요 → 켜기 | 받은 알림 그대로, 꺼 둔 동안 몫 없음 | US5, SC-005 |
| 18 | 보관 기간 | 7일로 바꾸기(안내 확인 창) → MutableClock 8일 뒤 04:00 | 7일 지난 알림 사라짐 | D-102 #27 |
| 19 | 신고 접수처 | member 글, owner 글, 블로그, 메인 프로필 회원 신고 | BLOG(운영 화면 신고 탭) / ADMIN / ADMIN / ADMIN | US6, SC-009 |
| 20 | 2주 제한 | 같은 글 다시 신고, MutableClock 15일 뒤 | 409 + 다시 신고할 수 있는 날짜 / 성공 | SC-008 |
| 21 | 신고 결과 | owner가 신고를 "경고"로 처리 | 신고자에게 운영 탭 결과 알림, 신고 탭에 신고자 없음 | FR-051, D-102 #15 |
| 22 | 팔로워 목록 | 팔로워 25명 시드 회원 프로필 → 팔로워 탭 | 20명 + 2페이지 5명, 닉네임·사진만 | US7, D-102 #9 |
| 23 | 차단 | 서로 팔로우하는 둘에서 차단 → 피드·검색·다른 블로그·같은 블로그 | 팔로우 둘 다 해제, 같은 블로그 안에서만 보임 | US8, SC-011 |
| 24 | 차단과 참여 신청 | owner가 대기 신청 중인 newbie 차단 | 신청 자동 거절 + 거절 알림, 7일 안 재신청 막힘 | D-102 #13 |
| 25 | 탈퇴 | 팔로우·구독·차단이 있는 회원 탈퇴 | 관계 즉시 사라짐, 그 회원의 신고는 남음 | D-102 #16 |
| 26 | 화면 | 360px 폭에서 사이드바·프로필·알림 설정·차단 목록 | 가로 스크롤 없음, 상단 메뉴 같음 | 4.2 |

## 확인 결과

2026-10-08 구현 후 통합 테스트(Testcontainers MySQL, MutableClock)로 확인했다. 전체 테스트: 526개 중 525개 통과·실패 0, 1개는 기존 `UiPreviewServer`(화면 미리보기용, 일부러 건너뜀).

| # | 확인한 테스트 | 결과 |
|---|---|---|
| 1~4 | `NotificationInboxIntegrationTest`(탭·더 보기 20건·읽음·하나/탭/전체 삭제·남의 알림 404) | 통과 |
| 5·6 | `NotificationPollingSessionTest`(안 읽은 개수 100에서 멈춤, X-User-Activity 없는 폴링은 30분 무활동 로그아웃을 늦추지 않음) | 통과 |
| 7 | `NotificationInboxIntegrationTest`(R-06 이동 주소: 글·프로필·블로그·신청 탭·블로그 홈·내용만) | 통과 |
| 8·9 | `MandatoryNotificationIntegrationTest`(9가지를 꺼도 폐쇄 예정·철회·위임·경고 알림 옴, 폐쇄 버튼 뒤 구독자도 3일 전부터 한 번) | 통과 |
| 10~12 | `ProfileIntegrationTest`(닉네임·사진·소개·공개 블로그·팔로워 수, 개인정보 없음, 소개 500/501자, 본인만 숨긴·비공개 블로그) | 통과 |
| 13~15 | `FollowIntegrationTest`(팔로워 수 1·0·1, 새 팔로워 알림 1건, 자기 자신 400, 관리자 403, 31번째 429, 동시 10번 1건) | 통과 |
| 16 | `SubscriptionIntegrationTest`(구독 알림, 블로그장 400, 관리자 403, 요청 제한) | 통과 |
| 17·18 | `NotificationSettingsIntegrationTest`, `NotificationRetentionIntegrationTest`(끈 동안 몫 없음, 7일·30일 04:00 정리, 1000건씩 지움) | 통과 |
| 19·20 | `ReportIntegrationTest`(접수처 BLOG·ADMIN, 비멤버 404, 9일째 409 + reportableAt·14일째 성공, 동시 2번 1건, 사유·설명 400, 자기 것 400, 공지 400, 당시 내용이 글 정리 뒤에도 남음) | 통과 |
| 21 | `ReportResultNotificationTest`, `BlogReportIntegrationTest`(네 가지 결과 → 운영 탭 1건, 끄면 없음, 탈퇴 신고자 없음, 관리자 결과 문구) | 통과 |
| 22 | `FollowListIntegrationTest`(25명 → 20·5, 최근 순, 닉네임·사진만, 탈퇴 회원 빠짐, 없는 회원 404) | 통과 |
| 23·24 | `BlockIntegrationTest`(두 방향 팔로우 삭제, 블로그 글 목록·피드·검색·태그·댓글에서 빠짐, 같은 블로그 멤버면 보임, 행동 알림 없음, 블로그장 차단 시 대기 신청 자동 거절 + 7일 규칙, 부블로그장 차단은 영향 없음) | 통과 |
| 25 | `WithdrawalSocialCleanupIntegrationTest`(관계 즉시 삭제, 신고 남음) | 통과 |
| 보안 | `SocialSecurityTest`(응답·로그에 이메일·이름·전화번호 없음, CSRF 없는 쓰기 12가지 403, 공격 문자열은 JSON 문자열), `OpenApiConformanceTest`(계약 15개 경로 매핑, 계약 밖 API 없음) | 통과 |
| 성능 | `SocialResponseTimeTest`(팔로워 5,000명 프로필·목록, 알림 3,000건 목록·개수 2초 안) | 통과 |
| 시드 | `SeedSqlTest`(`local/seed.sql`의 팔로우·구독·탭 5가지 알림·알림 설정이 스키마에 들어감) | 통과 |

확인하지 못한 것:

- 26(360px·PC 화면), 1의 종 아이콘·사이드바 모양, 5의 실제 30초 배지 갱신은 브라우저로 보지 못했다(이 작업에서는 서버를 띄우지 않음). 화면 코드는 기존 CSS 클래스만 쓰고 글자는 textContent로 넣었다. 사람이 `bootRun` 뒤 확인해야 한다.
- 2·22의 "시드 25건·팔로워 25명"은 시드에 넣지 않았다(시드는 탭마다 1건씩). 같은 내용은 테스트가 데이터를 만들어 확인했다.
- Crowfoot DB(cf_u33_d1)에는 003 시드를 넣지 않았다.
