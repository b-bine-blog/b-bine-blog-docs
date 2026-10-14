---
description: "003 소셜·알림 구현 작업 목록"
---

# 작업 목록 (Tasks): 소셜(팔로우·구독·차단·신고)과 알림

**입력**: `specs/003-social-notification/`의 설계 문서

**선행 문서**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/social-api.yaml](contracts/social-api.yaml), [quickstart.md](quickstart.md)

**테스트**: 성공 기준(SC-001~SC-012)이 경계값(30초, 99개, 14일, 30일·7일, 1분 30번, 0건)으로 정해져 있다. 그래서 스토리마다 테스트 작업을 두고 테스트를 먼저 쓴다.

**구성**: 사용자 스토리(US1~US8)별로 묶었다. 001·002·004의 부품(`IntegrationTestBase`, `BlogTestBase`, `BoardTestBase`, `BlogPermissionService`, `PostPolicy`, `PostVisibility`, `NotificationWriter`, `SubscriptionService`, `JoinService`, `BlogReportService`, `RateLimiter`, `DailyCleanupJob`, `api.js`, `layout.js`)을 그대로 쓰고, 이미 있는 기능은 다시 만들지 않는다(research R-01).

## 형식: `[ID] [P?] [Story] 설명`

- **[P]**: 동시에 해도 되는 작업(다른 파일, 끝나지 않은 작업에 의존하지 않음)
- **[Story]**: 이 작업이 속한 사용자 스토리(US1~US8)
- 경로 약속: 소스 `src/main/java/com/mainblog/`, 테스트 `src/test/java/com/mainblog/`, 화면 `src/main/resources/static/`
- 커밋 메시지에 작업 ID와 요구사항 ID를 적는다. 예: `T024 팔로우 (SOC-01, D-102 #3)`

---

## 1단계: 준비 (Setup)

- [X] T001 `src/main/resources/application.yml`에 data-model "설정값"의 `social.*`, `notification.*`을 `${ENV:기본값}`으로 더한다 (D-68)
- [X] T002 [P] `src/main/java/com/mainblog/common/config/SocialProperties.java`, `NotificationProperties.java`를 `@ConfigurationProperties` + `@Validated`로 만든다. `social.bio.max-length`·`social.report.detail-max-length`는 `@Max(500)`(DB 칸 길이), `notification.retention.*`은 7·30만 받게 검사한다
- [X] T003 [P] `src/main/java/com/mainblog/common/config/SecurityConfig.java`에 비회원도 보는 `GET /api/users/*/profile`, `/api/users/*/followers`, `/api/users/*/following`을 permitAll로 더한다 (FR-005, D-102 #8·#9)
- [X] T004 [P] `src/main/java/com/mainblog/common/error/ErrorCode.java`에 `SELF_NOT_ALLOWED`(400), `FOLLOW_NOT_ALLOWED`(403, "이 회원을 팔로우할 수 없습니다."), `REPORT_TOO_SOON`(409)을 더한다. 나머지는 기존 코드(`ADMIN_NOT_ALLOWED`, `NOT_FOUND`, `RATE_LIMITED`, `VALIDATION_FAILED`, `POST_NOT_FOUND`, `COMMENT_NOT_FOUND`, `BLOG_NOT_FOUND`, `BLOG_SUSPENDED`)를 쓴다 (contracts)

---

## 2단계: 기반 (Foundational)

**⚠️ 중요**: 이 단계를 끝내기 전에는 어떤 사용자 스토리도 시작하지 않는다.

- [X] T005 `src/main/java/com/mainblog/common/notification/NotificationType.java`에 `NEW_FOLLOWER`(FOLLOW, new_follower), `BLOG_SUBSCRIBED`(SUBSCRIBE, blog_subscribed)와 `blockable` 표시(POST_COMMENT, COMMENT_REPLY, POST_LIKE, NEW_FOLLOWER, BLOG_SUBSCRIBED, JOIN_REQUESTED)를 더하고, `NotificationWriter.java`가 받는 사람이 탈퇴했거나 `blockable` 알림의 행동한 회원을 차단했으면 만들지 않게 한다. `src/test/java/com/mainblog/common/notification/NotificationWriterTest.java`에 경우를 더한다 (research R-07, D-102 #11)
- [X] T006 [P] `src/main/java/com/mainblog/social/application/SocialGuard.java`: 로그인 회원이 관리자면 403 `ADMIN_NOT_ALLOWED`, 대상 회원이 없거나 탈퇴·관리자면 404 `NOT_FOUND`, 두 회원 사이 차단 여부(어느 방향이든)를 DB로 확인한다 (D-90, research 가정 1)
- [X] T007 [P] `src/test/java/com/mainblog/social/SocialTestBase.java`에 알림 넣기(받는 사람·종류·탭·받은 시각), 팔로우·차단·구독·신고 행 넣기, 알림 설정 바꾸기 도우미를 둔다(`BoardTestBase` 확장)

**체크포인트**: 기반 준비 완료.

---

## 3단계: 사용자 스토리 1 - 종 아이콘으로 알림함 보기 (P1) 🎯 MVP

**독립 테스트**: 탭마다 알림을 넣어 두고 목록·탭·읽음·모두 읽음·하나 삭제·전체 삭제를 해 보고, 새 알림이 30초 확인에 잡히는지와 확인 요청이 로그인을 늘리지 않는지 본다.

- [X] T008 [P] [US1] `src/test/java/com/mainblog/notification/NotificationInboxIntegrationTest.java`: ALL에 모두, COMMENT 탭에 댓글만, FOLLOW 탭에 새 팔로워 + 블로그 구독, 최신순 20개 + `before`로 다음 묶음·`hasMore`, 남의 알림 안 보임·읽음·삭제 404, 목록 조회만으로 읽음 안 됨, 하나 읽음, 보고 있는 탭만 모두 읽음, 하나 삭제, COMMENT 탭 전체 삭제는 그 탭만·ALL은 모두(바로 행 삭제), 종류별 `link`(글·공지·프로필·블로그·신청 목록·위임은 블로그 홈·운영 알림 null), 글이 지워지면 `link` null, 비회원 401 (US1-1~5·8, FR-029~FR-031, FR-033, D-102 #17~#19·#21·#28)
- [X] T009 [P] [US1] `src/test/java/com/mainblog/notification/NotificationPollingSessionTest.java`: `unread-count`가 안 읽은 수와 `pollIntervalSeconds` 30을 주고 150건이면 100에서 멈춤, 새 알림이 다음 확인에 잡힘, "로그인 유지" 미체크 로그인에서 헤더 없는 `unread-count`만 30초마다 31분 보내면 refresh 401, `X-User-Activity: 1` 요청이 있으면 유지 (US1-6·7, SC-001, SC-012, D-62, D-102 #20)
- [X] T010 [US1] `src/main/java/com/mainblog/notification/application/NotificationLinkResolver.java`: research R-06 표대로 `target_type`·`target_id`에서 이동할 주소를 만들고 대상이 없으면 null (D-102 #21)
- [X] T011 [US1] `src/main/java/com/mainblog/notification/application/NotificationQueryService.java`(목록·개수), `NotificationCommandService.java`(읽음·모두 읽음·삭제)와 `src/main/java/com/mainblog/notification/api/NotificationController.java`(`GET·DELETE /api/notifications`, `GET /api/notifications/unread-count`, `DELETE /api/notifications/{id}`, `POST /api/notifications/{id}/read`, `POST /api/notifications/read-all`)를 만든다. API `tab=FOLLOW`는 `FOLLOW`·`SUBSCRIBE`를 함께 본다 (contracts, research R-03·R-04)
- [X] T012 [US1] 화면 `src/main/resources/static/js/layout.js`에 종 아이콘·배지(99 넘으면 "99+")를 넣고, `src/main/resources/static/js/notifications.js`를 새로 만든다: 30초마다 `api.get('/api/notifications/unread-count')`를 `{activity: true}` 없이 부르고 401이면 멈추며, 오른쪽 사이드바(탭 6개, 안 읽음 강조, 누르면 읽음 → `link` 이동 또는 내용 펼침·"볼 수 없는 내용입니다", 모두 읽음, x, 확인 창 뒤 전체 삭제, 더 보기)를 모두 textContent로 그린다. `src/main/resources/static/css/base.css`에 종·배지·사이드바(PC 360px, 600px 이하 전체 화면) 스타일을 더한다 (FR-028~FR-033, D-64, D-72)
- [X] T013 [US1] `src/main/resources/static/js/blog-manage.js`가 주소의 `?tab=` 값(예: `requests`)을 읽어 권한이 있으면 그 탭을 먼저 연다 (research R-06)

**체크포인트**: 모든 화면에서 알림함이 열리고 30초마다 개수가 바뀐다.

---

## 4단계: 사용자 스토리 2 - 블로그 운영에 꼭 필요한 알림 받기 (P1)

**독립 테스트**: 끌 수 있는 알림을 모두 끈 회원들로 폐쇄·철회·위임·비공개 전환·글 삭제·제재·해제 문의를 일으켜 받는 사람과 탭을 확인한다. 대부분 002·004에 이미 있는 동작이라 테스트로 확인하고, 다른 곳만 고친다.

- [X] T014 [P] [US2] `src/test/java/com/mainblog/notification/MandatoryNotificationIntegrationTest.java`: 받는 사람이 9가지를 모두 끈 상태에서 폐쇄 버튼 → 부블로그장·멤버·구독자는 즉시 받고 블로그장·다른 블로그 멤버는 안 받음, 3일 전·1일 전(MutableClock) 한 번씩, 멤버이면서 구독자는 한 번, 그 사이 들어온 구독자는 3일 전부터 받음, 서버가 꺼졌던 날 몫은 다음 실행에 한 번, 철회 알림 뒤 더 안 감, 위임 요청·수락·거절·7일 자동 취소, 폐쇄 버튼으로 취소된 위임은 받는 멤버에게 별도 알림 없음, 비공개 전환은 구독자 모두(바꾼 본인 제외, 일부 공개 전환은 없음), 내 글 삭제됨, 경고·정지·정지 해제·강제 퇴장, 해제 문의 결과, 각 알림의 탭이 3.6 표와 같음 (US2-1~12, SC-003, SC-004, D-102 #22~#25)
- [X] T015 [US2] (사용자 확인 뒤, plan "구현 전에 할 일" 1) `src/main/java/com/mainblog/common/notification/NotificationType.java`에서 `DELEGATION_REQUESTED`·`DELEGATION_ACCEPTED`·`DELEGATION_REJECTED`·`DELEGATION_CANCELED`·`APPEAL_RELEASED`·`APPEAL_REJECTED`의 탭을 `BLOG`로 바꾼다(지금 002 테스트에는 이 탭 값을 확인하는 곳이 없다). 개발 DB의 쌓인 행은 `UPDATE notifications SET tab = 'BLOG' WHERE notification_type IN (...)`로 맞춘다. 확인 전에는 T014의 탭 확인에서 이 종류만 빼 둔다 (FR-043, FR-044, FR-049, research R-03)
  - **진행 기록 (2026-10-08)**: 사용자 확인이 아직 오지 않아 추천안(3.6 표대로 `BLOG`)으로 진행했다. 탭 값 6개만 바꾼 것이라 되돌릴 수 있다. 개발 DB의 `UPDATE`는 저장소에서 실행하지 않았다(아래 "구현하며 바뀐 점" 참고)
- [X] T016 [US2] `src/main/java/com/mainblog/blog/application/BlogService.java`의 `notifyPrivate`가 바꾼 본인을 빼게 한다 (FR-048, D-102 #25)

**체크포인트**: 끌 수 없는 알림이 설정과 관계없이 정해진 사람에게만 간다.

---

## 5단계: 사용자 스토리 3 - 회원 프로필 보기와 소개 고치기 (P1)

- [X] T017 [P] [US3] `src/test/java/com/mainblog/social/ProfileIntegrationTest.java`: 블로그 2개 운영·1개 참여·팔로워 3명인 회원의 프로필, 비회원도 200, 다른 사람에게 일부 공개·비공개·숨김·폐쇄 블로그 없음·본인에게는 일부 공개·비공개 있음, 탈퇴 회원·관리자·없는 번호 404, `viewer`(self·following·blocking)와 상대가 나를 차단했는지는 없음, 응답에 이메일·이름·전화번호 없음, 소개 0·500자 성공·501자 400·줄바꿈 유지·앞뒤 공백 제거·빈 값이면 null, 바뀐 소개가 프로필과 `GET /api/members/me`에 같게 보임, 남의 소개를 고칠 경로가 없음 (US3, SC-010, D-102 #6~#8)
- [X] T018 [US3] `src/main/java/com/mainblog/social/application/ProfileService.java`와 `src/main/java/com/mainblog/social/api/ProfileController.java`(`GET /api/users/{userId}/profile`, `PUT /api/members/me/bio`)를 만든다 (FR-001~FR-005, research R-09)
- [X] T019 [US3] `src/main/java/com/mainblog/social/api/SocialPageController.java`(`/profile/{id}` → `profile.html` forward)와 화면 `src/main/resources/static/profile.html` + `src/main/resources/static/js/profile.js`(닉네임·사진·소개 `white-space: pre-line`·운영·참여 블로그 링크·팔로워 수, 모두 textContent)를 만든다
- [X] T020 [P] [US3] `src/main/resources/static/me/index.html` + `src/main/resources/static/js/me.js`에 소개 고치기 칸(글자 수 표시 0/500), 내 프로필·알림 설정·차단 목록 링크를 더한다 (FR-004)
- [X] T021 [P] [US3] `src/main/resources/static/js/board-common.js`·`board-post.js`·`board-feed.js`에서 작성자 `state = ACTIVE`인 닉네임을 `/profile/{id}` 링크로 바꾼다 (FR-001)

**체크포인트**: 어디서든 닉네임을 눌러 프로필을 본다.

---

## 6단계: 사용자 스토리 4 - 회원 팔로우와 블로그 구독 (P2)

- [X] T022 [P] [US4] `src/test/java/com/mainblog/social/FollowIntegrationTest.java`: 팔로우 → 행 1개·팔로워 수 +1·NEW_FOLLOWER(FOLLOW 탭) 1건, 취소 → -1, 취소 후 다시 팔로우해도 알림 1건, 동시 10번 → 행 1개·알림 1건, 자기 자신 400 `SELF_NOT_ALLOWED`, 관리자 403 `ADMIN_NOT_ALLOWED`, 비회원 401, 탈퇴·관리자 대상 404, 어느 방향이든 차단이 있으면 403 `FOLLOW_NOT_ALLOWED`(문구에 "차단" 없음), 1분 31번째 429 `RATE_LIMITED`, new_follower 끄면 알림 없음, 팔로우 뒤 피드 팔로우 탭에 그 회원 글 (US4-1~3·7·8, SC-007, D-102 #1·#3·#4·#11)
- [X] T023 [P] [US4] `src/test/java/com/mainblog/social/SubscriptionIntegrationTest.java`: 공개 블로그 구독 → 블로그장에게 BLOG_SUBSCRIBED(SUBSCRIBE 탭) 1건·다시 구독해도 1건, 블로그장 400, 관리자 403, 비공개 블로그 비멤버 404·멤버 성공, 일부 공개는 공유 쿠키로 들어온 회원 성공·비회원 401·자동 구독 없음, 구독 목록에서 링크 없이 들어감, 1분 31번째 429, 블로그가 폐쇄되면(04:00) 구독 행 삭제·내 구독 목록에서 사라짐·별도 알림 없음, 블로그장이 차단한 회원의 구독은 알림 없음 (US4-4~6, FR-007~FR-011, D-102 #1·#2·#4·#5)
- [X] T024 [US4] `src/main/java/com/mainblog/social/application/FollowService.java`와 `src/main/java/com/mainblog/social/api/FollowController.java`(`POST·DELETE /api/users/{userId}/follow`)를 만든다. 요청 제한 → 관리자 → 대상 → 자기 자신 → 차단 순서로 확인하고, `INSERT IGNORE`가 1행일 때만 NEW_FOLLOWER를 쓴다 (research R-10)
- [X] T025 [US4] `src/main/java/com/mainblog/blog/application/SubscriptionService.java`에 요청 제한·관리자·블로그장 확인과 BLOG_SUBSCRIBED 알림을 더하고, `BlogClosingService.java`의 `closeIfDue`가 폐쇄와 같은 트랜잭션에서 그 블로그의 구독을 지우게 한다 (research R-11, D-102 #5)
- [X] T026 [US4] `src/main/resources/static/js/profile.js`에 팔로우·취소 버튼(로그인 회원, 본인·관리자에게는 숨김, 429·403 문구 그대로 표시)을 붙인다
- [X] T027 [US4] `src/main/resources/static/js/blog-home.js`의 구독 버튼을 블로그장·관리자에게 숨기고, 400·429 응답의 `message`를 보여준다

---

## 7단계: 사용자 스토리 5 - 알림 종류 켜고 끄기와 보관 기간 정하기 (P2)

- [X] T028 [P] [US5] `src/test/java/com/mainblog/notification/NotificationSettingsIntegrationTest.java`: 처음 조회는 9가지 모두 true·30일, 일부만 보내면 그것만 바뀜, `blogClosing` 같은 다른 키 400 `NotAllowed`, `retentionDays` 14 → 400, post_like를 끄면 받은 3건은 그대로·새 좋아요 알림 없음·다시 켜도 꺼 둔 동안 몫은 안 생김, 다 꺼도 폐쇄 예정은 옴, 남의 설정 경로 없음 (US5-1~4, SC-005, D-102 #26)
- [X] T029 [P] [US5] `src/test/java/com/mainblog/notification/NotificationRetentionIntegrationTest.java`: 기본 30일(29일째 남음, 31일째 04:00 뒤 사라짐), 7일로 줄이면 다음 04:00에 이미 7일 지난 것까지 사라짐, 30일로 되돌려도 안 돌아옴, 하루 건너뛴 뒤 다음 실행에 밀린 것까지 삭제, 다른 회원 알림은 그대로 (US5-5~7, SC-006, D-102 #27)
- [X] T030 [US5] `src/main/java/com/mainblog/notification/application/NotificationSettingsService.java`와 `src/main/java/com/mainblog/notification/api/NotificationSettingsController.java`(`GET·PUT /api/me/notification-settings`, `INSERT ... ON DUPLICATE KEY UPDATE`)를 만든다 (FR-054, FR-057, research R-08)
- [X] T031 [US5] `src/main/java/com/mainblog/notification/application/NotificationDailyTasks.java`(보관 7일 회원·그 밖 30일 기준 삭제, 1,000건씩)를 만들고 `src/main/java/com/mainblog/batch/DailyCleanupJob.java`의 단계와 로그에 더한다 (FR-056, SCL-03)
- [X] T032 [US5] 화면 `src/main/resources/static/me/notifications.html` + `src/main/resources/static/js/me-notifications.js`: 체크박스 9개, 보관 기간 30일·7일(7일로 바꿀 때 "7일이 지난 알림은 다음 정리 때 지워집니다" 확인 창), 알림 일괄 삭제(확인 창). 끌 수 없는 알림은 체크박스 없이 안내 문구로만 (FR-054, FR-057, D-102 #27)

---

## 8단계: 사용자 스토리 6 - 회원·블로그·글·댓글 신고 (P2)

- [X] T033 [P] [US6] `src/test/java/com/mainblog/social/ReportIntegrationTest.java`: 멤버 글 → BLOG(002 신고 목록에 블로그장·멤버 관리 부블로그장에게 보이고 신고자 없음), 블로그장이 쓴 글·댓글 → ADMIN, 블로그 → ADMIN, 블로그 안 멤버 → BLOG·블로그장 → ADMIN·비멤버 404, 메인 프로필 회원 → ADMIN(blog_id NULL), 10월 1일 신고 후 10월 10일 409 `REPORT_TOO_SOON`+`reportableAt`·15일째 성공, 다른 회원 신고는 따로, 동시 2번 → 1건, 사유 목록 밖 400·OTHER 설명 없음 400·설명 501자 400, 자기 자신·내 글·내 댓글·내가 블로그장인 블로그 400 `SELF_NOT_ALLOWED`, 관리자 403, 볼 수 없는 글 404, 공지 글 400, `target_snapshot`에 당시 내용(이메일·전화번호 없음)이 남고 글이 30일 정리된 뒤에도 남음, 신고당한 회원에게 알림 없음 (US6-1~4·8~10, SC-008, SC-009, D-93, D-102 #1·#14·#15)
- [X] T034 [P] [US6] `src/test/java/com/mainblog/social/ReportResultNotificationTest.java`: 블로그장이 문제 없음·경고·정지·강제 퇴장으로 처리하면 신고자에게 REPORT_RESOLVED(운영 탭) 1건, report_result를 끄면 알림 없음·처리는 됨, 신고자가 탈퇴했으면 없음, `ReportResultNotifier`가 관리자 결과(OWNER_WARNING·OWNER_KICK·BLOG_CLOSE) 문구를 만듦 (US6-5~7, FR-051)
- [X] T035 [US6] `src/main/java/com/mainblog/social/application/ReportReasons.java`(설정값 사유 읽기), `ReportService.java`(대상 확인·접수처·자기 것·신고자 행 잠금 + 14일 확인·당시 내용 JSON)와 `src/main/java/com/mainblog/social/api/ReportController.java`(`POST /api/reports`, `GET /api/reports/reasons`)를 만든다 (FR-022~FR-025, FR-027, research R-14)
- [X] T036 [US6] `src/main/java/com/mainblog/social/application/ReportResultNotifier.java`를 만들고 `src/main/java/com/mainblog/blog/application/BlogReportService.java`의 결과 알림을 이것으로 바꾼다(동작 같음, 005도 쓴다) (FR-051, research R-15)
- [X] T037 [US6] 화면 `src/main/resources/static/js/report.js`(사유 라디오는 `/api/reports/reasons`로, 설명 칸 글자 수, 접수처 안내, 409면 다시 신고할 수 있는 날짜)를 만들고 `board-post.js`(글·댓글·작성자 신고, 블로그 안이면 blogId), `blog-home.js`(블로그 신고), `profile.js`(메인 프로필 회원 신고)에 붙인다 (FR-022)

---

## 9단계: 사용자 스토리 7 - 팔로워·팔로잉 목록 보기 (P3)

- [X] T038 [P] [US7] `src/test/java/com/mainblog/social/FollowListIntegrationTest.java`: P의 팔로워 A·B, 팔로잉 C, 최근 팔로우 순, 25명이면 20·5 두 페이지, 항목은 id·닉네임·사진만(이메일·이름·전화번호 없음), A가 언팔로우하면 빠짐, 비회원 200, 탈퇴 회원 안 나옴, 없는 회원 404 (US7, D-102 #9)
- [X] T039 [US7] `FollowService`·`FollowController`에 `GET /api/users/{userId}/followers`, `GET /api/users/{userId}/following`(번호 페이지 20명)을 더한다 (FR-015, research R-12)
- [X] T040 [US7] `src/main/resources/static/js/profile.js`에 팔로워·팔로잉 탭과 번호 페이지를 붙인다(닉네임은 프로필 링크, textContent)

---

## 10단계: 사용자 스토리 8 - 회원 차단 (P3)

- [X] T041 [P] [US8] `src/test/java/com/mainblog/social/BlockIntegrationTest.java`: 서로 팔로우하던 A가 B를 차단하면 두 방향 팔로우 삭제, A의 피드·검색·태그·멤버가 아닌 블로그 K 글 목록·댓글에서 B 빠짐, 둘 다 멤버인 블로그 J에서는 보임, B에게는 A 글이 그대로 보임, 차단 중 서로 팔로우 403, B의 댓글·대댓글·좋아요·구독은 A에게 알림 없음·끌 수 없는 알림은 그대로, 블로그장 O가 B를 차단하면 대기 중 신청 자동 거절 + JOIN_REJECTED + 7일 안 재신청 409, 차단 뒤 신청도 자동 거절(기존), 부블로그장의 차단은 신청에 영향 없음, 해제해도 팔로우 안 돌아옴, 차단 목록 닉네임·날짜·20개 페이지, 자기 자신 400, 관리자 403, B가 받는 어떤 응답에도 차단 사실 없음 (US8, SC-011, D-102 #10~#13)
- [X] T042 [US8] `src/main/java/com/mainblog/social/application/BlockService.java`와 `src/main/java/com/mainblog/social/api/BlockController.java`(`POST·DELETE /api/users/{userId}/block`, `GET /api/me/blocks`)를 만들고, `src/main/java/com/mainblog/blog/application/JoinService.java`에 `rejectPendingBlockedByOwner(ownerId, blockedId)`(블로그 행 잠금, AUTO_REJECTED, 처리 시각, JOIN_REJECTED)를 더한다 (FR-016, FR-019, FR-020, research R-13)
- [X] T043 [US8] `src/main/java/com/mainblog/board/application/PostListService.java`의 `blogPosts`에 `PostVisibility.notBlocked`를 붙인다(같은 블로그 멤버 예외는 조건에 이미 있음) (FR-017, FR-018)
- [X] T044 [US8] `src/main/resources/static/js/profile.js`에 차단·해제 버튼(확인 창)을 붙이고, 화면 `src/main/resources/static/me/blocks.html` + `src/main/resources/static/js/me-blocks.js`(목록·해제·번호 페이지)를 만든다 (FR-016)

---

## 11단계: 다듬기 (Polish)

- [X] T045 `src/main/java/com/mainblog/social/application/SocialCleanup.java`(팔로우 두 방향·구독·차단 두 방향 삭제)를 만들어 `src/main/java/com/mainblog/member/application/WithdrawalService.java`가 같은 트랜잭션에서 부르게 하고, `src/test/java/com/mainblog/social/WithdrawalSocialCleanupIntegrationTest.java`로 관계는 즉시 사라지고 그 회원의 신고는 남는 것을 확인한다 (D-102 #16)
- [X] T046 [P] `src/test/java/com/mainblog/contract/OpenApiConformanceTest.java`에 `SOCIAL_CONTRACT = specs/003-social-notification/contracts/social-api.yaml`을 더해 경로·메서드 대조와 "계약에 없는 API 없음"에 넣는다 (`BOARD_CONTRACT`와 같은 방식)
- [X] T047 [P] `src/test/java/com/mainblog/social/SocialSecurityTest.java`: 프로필·팔로워·팔로잉·차단 목록·알림 목록·신고 응답과 로그에 이메일·이름·전화번호 없음, 상태를 바꾸는 API 모두 CSRF 없으면 403, 공격 문자열을 소개·신고 설명·닉네임에 넣어도 응답이 JSON 문자열, 남의 알림 번호로 읽음·삭제 404 (SC-010, SEC-10, D-22, D-64)
- [X] T048 [P] `src/test/java/com/mainblog/perf/SocialResponseTimeTest.java`: 팔로워 5,000명 회원의 프로필·팔로워 목록, 알림 3,000건 회원의 알림 목록·안 읽은 개수가 2초 안 (SC-002)
- [X] T049 `local/seed.sql`에 팔로우·구독·알림(탭마다)·알림 설정 예시를 더하고, 종 아이콘·사이드바·프로필·알림 설정·차단 목록을 360px·PC에서 확인한다 (4.2)
- [X] T050 quickstart.md "확인 결과"를 채우고, 저장소 `README.md` 기능 목록과 `specs/README.md`의 003 확인 필요 항목 수(0, D-102)를 갱신한다

---

## 의존 관계와 실행 순서

- 1단계 → 2단계 → US1(MVP) → 나머지 스토리.
- US2는 US1 뒤(탭 확인). T015는 사용자 확인을 받은 뒤에 한다.
- US3 → US4(팔로우 버튼이 프로필 화면에 붙음) → US7(목록이 프로필 화면에 붙음). US5·US6은 US1 뒤에 서로 독립이다. US8은 US3·US4 뒤(차단 버튼과 팔로우 삭제).
- 11단계(다듬기)는 모든 스토리 뒤.
- 같은 파일(`profile.js`, `blog-home.js`, `board-post.js`, `ErrorCode.java`, `NotificationType.java`)을 고치는 작업은 차례로 한다.

---

## 구현하며 바뀐 점

- **T015 알림 탭**: 사용자 확인 없이 추천안(3.6 표대로 위임 요청·결과, 블랙리스트 해제 문의 결과를 `BLOG` 탭으로)으로 진행했다. 개발 DB의 `UPDATE notifications SET tab = 'BLOG' ...`는 실행하지 않았다(이미 쌓인 행은 `OPERATION` 탭에 남는다). 다르게 정하면 `NotificationType` 6줄만 되돌린다.
- **T019·T040·T044 profile.js**: 프로필 화면을 T019에서 팔로우·차단·신고·팔로워 목록까지 한 번에 만들었다. T040·T044는 서버 API와 `me/blocks.html`만 더했다.
- **T021 board-feed.js**: 피드 목록은 `board.renderPosts`(→ `authorNode`)를 써서 따로 고치지 않았다.
- **요청 제한 테스트 격리**: 메모리 요청 제한(`InMemoryRateLimiter`)이 테스트 사이에 남아(회원 번호가 1부터 다시 시작, 시계 고정) 429가 번졌다. `IntegrationTestBase`의 `@BeforeEach`에서 버킷을 비운다(운영 코드는 그대로).
- **알림 설정 API**: 본문을 `Map`으로 받아 모르는 키는 400 `NotAllowed`, 참·거짓이 아닌 값은 `Type`, 보관 기간 7·30 밖은 `Allowed`로 돌려준다(일부 키만 보내면 그 키만 바꾼다).
- **새 팔로워 알림**: `target_type = 'USER'`, `target_id`·`actor_id` = 팔로우한 회원(R-06 이동이 프로필로 간다).
- **보관 기간 정리**: 받은 지 꼬박 30일(7일)이 지난 뒤 처음 오는 04:00에 지운다(1000건씩 나눠 지움).
- **신고 결과 알림 대상**: 블로그 안 신고는 `target_type = 'BLOG'`(그 블로그 홈으로 이동), 메인 프로필 신고처럼 블로그가 없으면 `target_type = 'REPORT'`(내용만 보임). 문구에 신고당한 회원 닉네임은 넣지 않는다.
- **신고 2주 제한의 동시성**: 신고자 `users` 행을 `FOR UPDATE`로 잠근 뒤 직전 신고 시각도 잠금 읽기(`FOR SHARE`)로 읽는다. 잠금 전에 다른 조회가 있어 REPEATABLE READ 스냅숏이 앞 요청의 새 행을 못 보는 것을 피했다.
- **공지 글 신고**: 400 `VALIDATION_FAILED`(field `targetId`, code `NotAllowed`).
- **차단 해제·차단 목록**: 해제는 대상이 관리자·탈퇴 회원이어도 204(없는 차단 지우기). 차단 목록은 탈퇴하지 않은 회원만 보인다(탈퇴하면 관계가 지워진다).
- **목록 페이지 크기**: 팔로워·팔로잉·차단 목록은 `social.list.page-size`(20), 페이지 값 확인은 004의 `BoardPaging`(1 미만이면 400 `page`/`Min`)을 같이 쓴다.
- **T049 화면 확인**: 360px·PC 화면은 서버를 띄우지 않아 직접 보지 못했다(quickstart "확인 결과"에 적음). 시드는 탭마다 1건씩이라 quickstart 2·22의 25건 예시는 테스트 데이터로만 확인했다. Crowfoot DB에는 003 시드를 넣지 않았다.
