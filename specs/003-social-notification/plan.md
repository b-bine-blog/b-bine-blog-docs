# 구현 계획 (Implementation Plan): 소셜(팔로우·구독·차단·신고)과 알림

**브랜치**: `003-social-notification` | **날짜**: 2026-10-08 | **명세**: [spec.md](spec.md)

**입력**: `specs/003-social-notification/spec.md` (확인 필요 항목 0개, D-102까지 반영)

## 요약 (Summary)

회원이 다른 회원의 프로필을 보고 팔로우·차단·신고하고, 블로그를 구독한다. 모든 화면 위쪽의 종 아이콘으로 알림함을 열고, 30초마다 새 알림 개수를 확인하며, 내 정보에서 알림 종류와 보관 기간을 정한다.
001·002·004와 같은 Spring Boot 앱에 `social`·`notification` 패키지를 더한다.
- 002·004가 이미 알림 쓰기, 구독, 블로그 안 신고 처리, 폐쇄 알림, 차단·팔로우 읽기를 만들어 두었다. 003은 그것을 다시 만들지 않고 빠진 것만 더한다(research R-01).
- 30초 폴링은 001의 "활동 헤더가 있을 때만 로그인 연장" 장치를 그대로 쓴다. 폴링은 헤더 없이 보낸다(R-05).
- ERD: Crowfoot 문서 654의 테이블을 그대로 쓴다. **DB 구조 변경은 없다**. "미정"으로 남은 설명 문구 다섯 곳만 사용자 승인 뒤 Crowfoot에서 고친다(R-18).

## 기술 맥락 (Technical Context)

**언어/버전**: Java 21, Spring Boot 3.5.16

**주요 의존성**: 001·002·004와 같음. 새 라이브러리 없음.

**저장소**: MySQL 8(Crowfoot 문서 654)

**테스트**: JUnit 5, MockMvc, Testcontainers MySQL 8.0, `MutableClock`, `IntegrationTestBase`·`BlogTestBase`·`BoardTestBase`

**대상 플랫폼**: Linux 서버 1대(1차), PC·모바일 브라우저

**프로젝트 종류**: 웹 서비스(REST API + 정적 화면, 단일 Spring Boot 앱)

**성능 목표**: 알림 목록·개수, 프로필, 팔로워·팔로잉 목록, 내 구독 목록은 1초 목표, 2초 이내다(SC-002). 화면은 5초가 넘으면 중단하고 다시 시도하라고 안내한다(`api.js`).

**제약**:
- 서버에 상태를 두지 않는다. 알림·관계·신고는 DB에 둔다. 팔로우·구독 요청 제한만 001·004와 같이 `RateLimiter`(서버 메모리)를 쓴다.
- 숫자 규칙은 모두 `social.*`, `notification.*` 설정값으로 둔다(D-68).
- 응답의 회원 정보는 닉네임·프로필 사진·소개만이다(D-22).
- 화면은 모든 글자를 textContent로 넣는다(D-64). 003 화면에는 innerHTML을 쓰는 곳이 없다.
- 알림 자동 확인은 로그인 연장으로 세지 않는다(D-62, D-72).

**규모/범위**:
- 새 API 19개(경로 15개). 계약은 [contracts/social-api.yaml](contracts/social-api.yaml)에 있다. 002 경로 3개(구독·취소, 블로그 글 목록)는 경로를 두고 동작만 더한다.
- 화면: 종 아이콘·알림 사이드바(모든 화면), 프로필(`/profile/{회원 번호}`), 알림 설정, 차단 목록, 내 정보의 소개 칸, 신고 창(글·댓글·블로그·프로필에 붙임)
- 테이블 13개를 쓰고, 새로 만드는 테이블은 없다.

**API와 근거**:

| API | 근거 |
|---|---|
| `GET /api/users/{userId}/profile` | SOC-03, FR-001~FR-003, FR-005, D-102 #6·#8 |
| `PUT /api/members/me/bio` | SOC-03, FR-004, D-102 #7 |
| `GET /api/users/{userId}/followers`, `/following` | SOC-02, FR-015, D-102 #9 |
| `POST·DELETE /api/users/{userId}/follow` | SOC-01, FR-006, FR-008, FR-009, FR-014, FR-039, D-90, D-102 #1·#3·#4·#11 |
| (002) `POST·DELETE /api/blogs/{blogId}/subscription` 보강 | SOC-01, FR-007, FR-009, FR-040, D-102 #1·#2·#4 |
| `POST·DELETE /api/users/{userId}/block`, `GET /api/me/blocks` | SOC-05, FR-016, FR-019~FR-021, D-102 #10·#11·#13 |
| (004) `GET /api/blogs/{blogId}/posts` 차단 조건 | SOC-05, FR-017, FR-018, D-36 |
| `POST /api/reports`, `GET /api/reports/reasons` | SOC-06, FR-022~FR-025, FR-027, D-85, D-93, D-102 #1·#14·#15 |
| `GET·DELETE /api/notifications`, `DELETE /api/notifications/{id}`, `POST .../{id}/read`, `POST .../read-all` | SOC-04, FR-029~FR-031, FR-033, D-102 #17~#19·#21·#28 |
| `GET /api/notifications/unread-count` | SOC-04, FR-032, D-62, D-72, D-102 #20 |
| `GET·PUT /api/me/notification-settings` | SOC-04, FR-054, FR-055, FR-057, FR-058, D-102 #26·#27·#29 |

**다른 기능과 나눈 범위**:
- 002 블로그: 구독·내 구독 목록·비공개 전환 알림·폐쇄 알림·참여 신청 알림·블로그 안 신고 처리는 002 코드를 그대로 쓴다. 003은 구독 확인·구독 알림, 폐쇄 때 구독 삭제, 차단 때 대기 신청 자동 거절, 비공개 전환 알림의 본인 제외만 002 코드에 더한다.
- 004 게시판: 댓글·좋아요·글 삭제·공지 알림, 피드 팔로우 탭, 차단 숨김은 004 코드를 그대로 쓴다. 블로그 글 목록에만 차단 조건을 더하고, 작성자 닉네임을 프로필 링크로 바꾸고, 글·댓글에 신고 버튼을 붙인다.
- 005 관리자: `route = 'ADMIN'` 신고 목록·처리, 블로그장 경고·권한 박탈 알림, 1년 지난 신고 삭제는 005가 한다. 003은 접수와 접수처 결정, 결과 알림 부품(`ReportResultNotifier`)만 만든다.
- 001 회원: 탈퇴 때 소셜 관계를 지우는 호출만 `WithdrawalService`에 더한다.

## 헌장 확인 (Constitution Check)

*Phase 0 전 확인, Phase 1 설계 후 다시 확인함.*

| 원칙 | 이 계획에서 지키는 방법 | 결과 |
|---|---|---|
| I. 보안 우선 | 상태를 바꾸는 API(팔로우·차단·신고·읽음·삭제·설정·소개)는 모두 CSRF를 거친다. 소개·신고 설명·알림 문구는 화면에서 textContent로만 넣는다(R-17). 신고 대상 내용은 JSON으로 저장하고 화면에 그대로 내보내지 않는다. 알림 `link`는 서버가 만든 상대 경로뿐이다(R-06) | 통과 |
| II. 블로그별 역할 서버 확인 | 구독·신고는 요청마다 002 `BlogPermissionService`로 볼 수 있는지·정지를 확인한다. 신고 접수처의 블로그장 여부는 신고하는 순간 `blog_members`로 본다(R-14). 블로그 안 신고 처리는 002의 `MEMBER_MANAGE` 확인을 그대로 쓴다. 참여 신청 알림 대상은 002가 현재 역할로 정한다(FR-034). 권한표는 data-model에 있다 | 통과 |
| III. 개인정보 서버에서 가림 | 프로필·목록·차단 목록·알림·신고 응답 DTO에 이메일·이름·전화번호 칸이 없다. 신고 당시 내용에도 넣지 않는다. 신고자는 블로그장 화면에 없다(D-102 #15). `SocialSecurityTest`가 응답 전체를 검사한다(SC-010) | 통과 |
| IV. 서버에 상태를 두지 않음 | 팔로우·구독은 DB 유니크, 신고 2주 제한은 신고자 행 잠금, 알림은 `event_key` 유니크로 한 번만 만든다. 보관 정리는 ShedLock이 걸린 04:00 작업에 붙인다. 팔로우·구독 요청 제한만 `RateLimiter`(서버 메모리, 이중화 때 교체)를 쓴다 | 통과(001 R-08과 같은 예외) |
| V. 명세와 결정이 먼저 | 모든 API에 FR·D 번호가 있다. 문서에 없어 기본값으로 둔 것은 research에 *가정*으로 표시하고 아래에 모았다. 3.6 표와 코드가 다른 알림 탭은 고치기 전에 사용자에게 묻는다(아래 "구현 전에 할 일") | 통과(가정·확인 항목 보고) |
| VI. 단순하게 시작 | 새 테이블이 없다. 알림은 30초 폴링이고 개수만 받는다(D-72). 기존 구독·알림 쓰기 코드를 다시 만들지 않는다 | 통과 |

**설계 후 다시 확인**: data-model과 contracts에서 새로 생긴 위반은 없다. Crowfoot 변경은 설명 문구뿐이다.

## 확인할 가정 (문서에 없어 기본값으로 둔 것)

research.md 끝의 "가정 목록"과 같다. 다르면 고친다.

1. 메인 관리자 계정과 탈퇴한 회원은 프로필이 404이고 팔로우·차단·신고 대상이 아니다. 관리자 계정은 차단도 하지 않는다.
2. 차단 때문에 알림을 만들지 않는 것은 끌 수 있는 알림 가운데 행동한 회원이 있는 종류(댓글·대댓글·좋아요·새 팔로워·블로그 구독·참여 신청)뿐이다. 끌 수 없는 운영 알림은 그대로 보낸다.
3. 차단한 회원의 글은 목록·피드·검색·태그·댓글에서 빠지고, 글 주소로 직접 열면 보인다.
4. 차단 목록은 최근 차단 순 20개씩 번호 페이지다.
5. 블로그 안 회원 신고의 대상은 그 블로그의 멤버만이다. 공지 글은 신고 대상이 아니다.
6. 신고 2주 제한의 "같은 대상"은 대상 종류 + 번호로 보고, 어디서 신고했는지는 따지지 않는다.
7. 다시 팔로우·구독할 때 알림을 다시 보내지 않는 것은 이벤트 키로 막는다. 처음 알림이 지워진 뒤에는 다시 갈 수 있다(004 좋아요와 같음).

## 프로젝트 구조 (Project Structure)

### 문서 (이 기능)

```text
specs/003-social-notification/
├── spec.md
├── clarify-questions.md
├── plan.md              # 이 파일
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── social-api.yaml
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### 소스 코드 (저장소 루트, 001·002·004에 더하는 것)

```text
src/main/java/com/mainblog/
├── common/
│   ├── config/          # SocialProperties (social.*), NotificationProperties (notification.*), SecurityConfig(공개 GET 경로 추가)
│   ├── error/           # ErrorCode에 SELF_NOT_ALLOWED, FOLLOW_NOT_ALLOWED, REPORT_TOO_SOON 추가
│   └── notification/    # NotificationType에 NEW_FOLLOWER, BLOG_SUBSCRIBED, blockable 표시
│                        # NotificationWriter에 차단·탈퇴 확인
├── social/
│   ├── api/             # ProfileController(프로필·소개), FollowController(팔로우·목록), BlockController,
│   │                    # ReportController, SocialPageController(/profile/{id} forward)
│   └── application/     # SocialGuard(관리자·대상 회원·차단 확인), ProfileService, FollowService, BlockService,
│                        # ReportService(접수처·당시 내용·2주 제한), ReportReasons, ReportResultNotifier, SocialCleanup
├── notification/
│   ├── api/             # NotificationController, NotificationSettingsController
│   └── application/     # NotificationQueryService(목록·개수·link), NotificationCommandService(읽음·삭제),
│                        # NotificationLinkResolver, NotificationSettingsService, NotificationDailyTasks
├── blog/application/    # SubscriptionService 보강, BlogClosingService(폐쇄 때 구독 삭제), BlogService(비공개 알림 본인 제외),
│                        # JoinService.rejectPendingBlockedByOwner, BlogReportService → ReportResultNotifier
├── board/application/   # PostListService.blogPosts 차단 조건
├── member/application/  # WithdrawalService → SocialCleanup
└── batch/
    └── DailyCleanupJob.java   # NotificationDailyTasks 단계 추가(보관 기간 지난 알림 삭제)

src/main/resources/
├── application.yml      # social.*, notification.* (data-model "설정값")
└── static/
    ├── profile.html             # 프로필, 팔로워·팔로잉 목록
    ├── me/notifications.html    # 알림 설정·보관 기간·일괄 삭제
    ├── me/blocks.html           # 차단 목록
    ├── me/index.html            # 소개 칸, 링크 추가
    ├── css/base.css             # 종 아이콘, 사이드바, 배지, 프로필
    └── js/notifications.js, profile.js, report.js, me-notifications.js, me-blocks.js
                                 # layout.js(종 아이콘), me.js(소개), blog-home.js(구독 버튼·신고), blog-manage.js(?tab=),
                                 # board-post.js·board-common.js(신고 버튼, 닉네임 프로필 링크)

src/test/java/com/mainblog/
├── social/              # 사용자 스토리별 통합 테스트, SocialTestBase, SocialSecurityTest
├── notification/        # 알림함·폴링·설정·보관 통합 테스트
├── contract/            # OpenApiConformanceTest에 social-api.yaml 추가
└── perf/                # SocialResponseTimeTest(팔로워 5,000명, 알림 3,000건)
```

**구조 결정**: 소셜은 "회원 단위로 메인에서 한 번만 만들고 모든 블로그가 같이 쓴다"(3.3)라서 `blog`가 아니라 `social`에 둔다. 알림함은 모든 기능이 쓰는 통로라 `notification`에 따로 두고, 002부터 쓰던 쓰기 부품(`common/notification`)은 옮기지 않는다. 블로그 열람·역할 판단은 002의 `BlogPermissionService`, 글 열람은 004의 `PostPolicy`를 부른다.

## 구현 전에 할 일

1. **알림 탭 확인 (사용자 확인 필요)**: 3.6 표는 위임 요청·위임 결과·블랙리스트 해제 문의 결과를 "블로그" 탭으로 정했지만, 002 코드(`NotificationType`)와 002 data-model은 `OPERATION`(운영 탭)으로 되어 있다(research R-03). CLAUDE.md 규칙대로 코드를 고치기 전에 확인을 받는다. 확인되면 T015에서 탭 값만 바꾸고 개발 DB의 쌓인 행을 `UPDATE`로 맞춘다(구조 변경 아님). 확인 전에도 나머지 작업은 진행할 수 있다.
2. **Crowfoot 설명 문구 (사용자 승인 필요, 구조 변경 없음)**: 문서 654에서 `users.bio`, `reports.reason`, `reports.reason_detail`, `notification_settings` 설명의 "미정"을 D-102 값으로, `notifications.tab` 설명에 팔로우·구독 탭 묶음을 고친다(research R-18). 연결 DB 반영은 `plan_migration` → 사용자 승인 → `apply_migration` 순서로 한다. 앱과 테스트는 저장소의 `schema.sql`을 쓰므로 구현은 막히지 않는다.
3. **병합 순서**: 003 브랜치는 `004-board` 위에 있다. 004 PR → 003 PR 순서로 병합한다.

## 복잡도 기록 (Complexity Tracking)

헌장 위반 없음. 트래픽 제한의 서버 메모리 사용은 001 R-08에서 이미 받아들인 예외와 같다.
