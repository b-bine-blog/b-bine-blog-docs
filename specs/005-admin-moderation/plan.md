# 구현 계획 (Implementation Plan): 메인 관리자와 제재

**브랜치**: `005-admin-moderation` | **날짜**: 2026-10-08 | **명세**: [spec.md](spec.md)

**입력**: `specs/005-admin-moderation/spec.md` (확인 필요 항목 0개, D-103까지 반영)

## 요약 (Summary)

메인 관리자(users.role = ADMIN)가 `/admin` 화면에서 회원을 찾아보고(이메일·전화번호는 가린 값, "전체 보기"는 기록), 블로그를 숨기거나 강제 폐쇄하고, 블로그장에게 경고를 주거나 바로 강퇴한다.
관리자는 블로그·블로그장 신고를 처리하고, 글·댓글을 숨기거나 지우고 30일 안에 복구한다. 모든 조치는 관리자 활동 기록에 남고 1년 뒤 정리된다. 통계는 회원 수·블로그 수·일별 가입·글 수다.
001·002·004와 같은 Spring Boot 앱에 `admin` 패키지를 더한다.
- 관리자 확인: 이미 매 요청 DB에서 회원을 읽는 필터에 role 권한을 붙이고, `/api/admin/**`을 URL 단위로 막는다(R-02).
- 002에 이미 있는 강제 폐쇄(`BlogClosingService.closeBySystem`)와 박탈 후 승계(`OwnerSuccessionService`)를 API로 연다. 지금 관리자가 블로그를 관리할 수 없는 것은 이 API와 화면이 없어서다(R-01).
- ERD: 관리자 테이블 3개(`admin_actions`, `owner_warnings`, `owner_revocations`)는 Crowfoot 문서 654에 이미 있다. **DB 구조 변경은 NULL 허용 칸 2개**(`comments.deleted_by`, `owner_warnings.reason`)이고 사용자 승인이 필요하다(R-15). 승인 전에도 그 두 칸에 기대는 부분만 빼고 구현할 수 있다.

## 기술 맥락 (Technical Context)

**언어/버전**: Java 21, Spring Boot 3.5.16

**주요 의존성**: 001·002·004와 같음. 새 라이브러리 없음.

**저장소**: MySQL 8(Crowfoot 문서 654)

**테스트**: JUnit 5, MockMvc, Testcontainers MySQL 8.0, `MutableClock`, `IntegrationTestBase`·`BlogTestBase`·`BoardTestBase`

**대상 플랫폼**: Linux 서버 1대(1차), PC·모바일 브라우저

**프로젝트 종류**: 웹 서비스(REST API + 정적 화면, 단일 Spring Boot 앱)

**성능 목표**: 회원 검색·블로그 검색·신고함은 1초 목표, 2초 이내다(SC-001). 화면은 5초가 넘으면 중단하고 다시 시도하라고 안내한다.

**제약**:
- 서버에 상태를 두지 않는다. 경고 수·숨김·처리 상태는 모두 DB에 있다. "전체 보기" 요청 제한만 001과 같이 서버 메모리 `RateLimiter`다.
- 숫자 규칙은 모두 `admin.*` 설정값으로 둔다(D-68).
- 이메일·전화번호는 서버가 가린다(D-22). 원문은 "전체 보기" 응답뿐이다.
- 관리자 화면은 모든 값을 textContent로 넣는다(D-64).

**규모/범위**:
- API 28개(경로 22개, D-104로 강제 폐쇄 철회 DELETE를 더함). 계약은 [contracts/admin-api.yaml](contracts/admin-api.yaml)에 있다.
- 화면 1개(`/admin`, 탭 6개: 회원, 블로그, 신고, 글·댓글, 활동 기록, 통계)
- 기존 화면 고침: 상단 메뉴(관리자 링크), 글 상세("관리자가 숨긴 글" 표시), 댓글("관리자가 숨긴 댓글입니다" 자리)
- 테이블 12개를 쓴다. 새 테이블은 없고, 칸 2개를 더한다.

**다른 기능과 나눈 범위**:
- 003(소셜·알림): 005보다 먼저 구현된다. 005는 003이 만든 `reports` 행 가운데 `route = 'ADMIN'`만 읽고 처리한다. 알림은 `NotificationWriter`로 쓰기만 하고, 알림함·설정 화면은 003 것이다. 이 저장소에는 아직 003 plan이 없어 신고 행 모양과 알림 이름은 003 명세·D-102를 기준으로 가정했다(R-16). 테스트는 신고 행을 직접 넣는다.
- 002(블로그): 블로그 단위 제재·블로그 안 신고·폐쇄 철회는 002 그대로다. 005는 두 곳을 고친다.
  - `BlogAccessPolicy.canView`: 숨김 블로그 들어가기 막기
  - `BlogClosingService`: 이미 폐쇄 예정일 때 사유만 바꾸기, 박탈된 블로그장을 폐쇄 예정 알림에서 빼기(지금은 그 사람도 받음, R-09)
- 004(게시판): 005는 `PostQueryService`(숨긴 글은 작성자에게만), `CommentService`(숨긴 댓글 자리, `deleted_by`), `PostService.delete`(관리자 삭제는 005 서비스로, 알림 키에 삭제 시각) 세 곳을 고친다. 004 계약(`board-api.yaml`)에는 `PostDetail.hiddenByAdmin`, 댓글 `hidden` 필드를 더한다.

## 헌장 확인 (Constitution Check)

*Phase 0 전 확인, Phase 1 설계 후 다시 확인함.*

| 원칙 | 이 계획에서 지키는 방법 | 결과 |
|---|---|---|
| I. 보안 우선 | 상태를 바꾸는 관리자 요청은 모두 CSRF를 검사한다. "전체 보기"도 기록을 남기는 POST라 CSRF와 `no-store`가 붙는다(R-04). 관리자 화면 HTML은 role 확인 뒤에만 내려준다(R-03). 관리자 화면에는 본문도 HTML로 넣지 않는다 | 통과 |
| II. 역할을 매 요청 서버에서 확인 | `/api/admin/**`는 URL 단위 `hasAuthority("ADMIN")`이다. 권한은 매 요청 DB에서 읽은 role로 붙이고 토큰에는 넣지 않는다. 서비스에서 `AdminGuard`로 한 번 더 확인한다(R-02). role을 회수하면 다음 요청부터 403이다. `AdminSecurityTest`가 모든 관리자 경로를 비회원·회원·블로그장·부블로그장으로 불러 본다 | 통과 |
| III. 개인정보 서버에서 가림 | 회원 응답은 `EmailMasker`·`PhoneMasker`로 가린 값만 담는다. 원문은 "전체 보기"뿐이고, 그때마다 같은 트랜잭션에서 `PRIVACY_VIEW`를 기록한다(ADM-06). 다른 관리자 응답에는 닉네임만 있다. 운영 기록 1년 보관과 정리(4.5, D-60)는 R-13이다 | 통과 |
| IV. 서버에 상태를 두지 않음 | 경고 수·박탈·숨김·신고 처리는 DB 행 잠금으로 한 번만 일어난다(R-09, R-10). 1년 정리는 기존 ShedLock 작업의 단계다. "전체 보기" 요청 제한만 `RateLimiter`(서버 메모리)다 | 통과(001 R-08과 같은 예외) |
| V. 명세와 결정이 먼저 | 모든 API에 FR·D 번호가 있다. 문서에 없어 기본값으로 둔 것은 research에 *가정*으로 표시하고 아래에 모았다. DB 칸 추가는 Crowfoot 문서에서 먼저 고치고 승인을 받는다(R-15) | 통과(가정 보고, DB 변경 승인 대기) |
| VI. 단순하게 시작 | 새 테이블이 없다. 통계는 볼 때마다 쿼리로 센다. 관리자 등급은 두지 않는다(D-103 #20). 화면은 한 페이지에 탭으로 둔다 | 통과 |

**설계 후 다시 확인**: data-model과 contracts에서 새로 생긴 위반은 없다. 구조 변경은 칸 2개 추가이고 지우는 문장은 없다.

## 확인할 가정 (문서에 없어 기본값으로 둔 것)

research.md "가정 모음"의 14개다. 결과에 영향이 큰 것만 다시 적는다. 다르면 고친다.

1. 블로그가 없는 신고(메인 프로필 회원 신고)는 "문제 없음"으로만 처리한다. 관리자 조치는 블로그장·블로그 단위뿐이라서다(D-44).
2. 관리자는 관리자 화면에서 비공개·숨김 블로그의 글·댓글 내용도 본다. ADM-03을 판단하려면 필요하다.
3. 숨긴 글은 작성자가 링크로만 보고 목록에는 나오지 않는다. 작성자는 지울 수는 있지만 고칠 수 없다.
4. 새 블로그장(자동 위임)에게는 따로 알림을 보내지 않는다. 블로그 숨김을 풀 때도 알림이 없다. 3.6 표와 D-103에 없는 알림이라서다.
5. 답글이 남은 최상위 댓글을 숨기면 "관리자가 숨긴 댓글입니다" 자리로 남긴다.
6. "전체 보기"는 관리자 한 명당 1분에 30번까지다.
7. 003의 신고 행 모양과 알림 이름은 003 명세 기준이다. 003 plan이 나오면 맞춘다.

D-103 #8의 "D-94가 관리자 폐쇄도 블로그장이 철회할 수 있게 한 뜻이 맞는지" 확인 요청은 2026-10-08 답이 왔다(D-104): 관리자가 강제 폐쇄한 블로그는 블로그장이 철회할 수 없고 관리자만 철회한다. `BlogClosingService.withdraw`가 `close_reason = ADMIN`을 403 `ADMIN_CLOSE_LOCKED`로 막고, 관리자 철회는 `DELETE /api/admin/blogs/{blogId}/force-close`(`BlogClosingService.withdrawByAdmin`, 기록은 `RESTORE`·`BLOG`)로 한다.

## 프로젝트 구조 (Project Structure)

### 문서 (이 기능)

```text
specs/005-admin-moderation/
├── spec.md
├── clarify-questions.md
├── plan.md              # 이 파일
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── admin-api.yaml
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### 소스 코드 (저장소 루트, 001·002·004에 더하는 것)

```text
src/main/java/com/mainblog/
├── auth/security/JwtAuthenticationFilter.java   # role = ADMIN이면 ADMIN 권한(DB에서 읽은 값)
├── common/
│   ├── config/          # AdminProperties (admin.*), SecurityConfig(/api/admin/** hasAuthority, AccessDeniedHandler → ADMIN_ONLY)
│   ├── error/           # ErrorCode에 OWNER_CHANGED, ALREADY_HIDDEN, NOT_HIDDEN, NOT_RESTORABLE, BLOG_ALREADY_CLOSED
│   └── notification/    # NotificationType에 OWNER_WARNED, OWNER_REVOKED, BLOG_HIDDEN, POST_HIDDEN, POST_RESTORED
├── admin/
│   ├── api/             # AdminMemberController, AdminBlogController, AdminOwnerController, AdminReportController,
│   │                    # AdminContentController(글·댓글), AdminActionController, AdminStatsController, AdminPageController(/admin)
│   └── application/     # AdminGuard, AdminActionLog, AdminPaging, AdminMemberService(검색·상세·전체 보기),
│                        # AdminBlogService(검색·상세·숨김·강제 폐쇄), OwnerWarningService, OwnerRevocationService,
│                        # AdminReportService, AdminPostModerationService, AdminCommentModerationService,
│                        # AdminActionQueryService, AdminStatsService, AdminDailyTasks
├── blog/application/    # BlogAccessPolicy(숨김이면 멤버만), BlogClosingService(markAdminClose, 박탈된 사람 알림 제외)
├── board/application/   # PostQueryService(숨긴 글 작성자만), PostService(관리자 삭제 → 005, 알림 키), CommentService(숨김 자리, deleted_by)
└── batch/DailyCleanupJob.java   # AdminDailyTasks 단계 추가(운영 기록 1년 정리)

src/main/resources/
├── application.yml      # admin.* (data-model "설정값")
├── admin/index.html     # 관리자 화면(static 밖, AdminPageController가 role 확인 뒤 내려줌)
└── static/
    ├── js/admin-*.js    # admin-common, admin-members, admin-blogs, admin-reports, admin-content, admin-actions, admin-stats
    ├── js/layout.js     # 관리자면 "관리자" 링크, "블로그 만들기·내 블로그" 숨김
    ├── js/board-post.js # "관리자가 숨긴 글" 표시, 숨긴 댓글 자리
    └── css/base.css     # 관리자 표·탭(좁은 화면은 카드)

src/test/java/com/mainblog/
├── admin/               # AdminTestBase, 사용자 스토리별 통합 테스트, AdminSecurityTest, AdminDailyTasksIntegrationTest
├── contract/            # OpenApiConformanceTest에 ADMIN_CONTRACT(admin-api.yaml) 추가
└── perf/                # AdminResponseTimeTest(회원 10,000, 블로그 1,000, 신고 5,000)
```

**구조 결정**: 관리자 기능은 회원·블로그·게시판에 걸치므로 `admin` 패키지에 두고, 블로그 상태를 바꾸는 일은 002 서비스(`BlogClosingService`, `OwnerSuccessionService`)를 부른다. 관리자 쿼리는 여러 테이블을 묶는 조회라 004처럼 `JdbcTemplate`으로 쓴다. 관리자 화면 HTML만 static 밖에 두어 role 확인 뒤 내려준다.

## 구현 전에 할 일

1. **Crowfoot DB 변경 승인(사용자 승인 필요)**: 칸 2개를 더한다. 둘 다 NULL 허용이고 지우는 문장은 없다(research R-15).
   - `comments.deleted_by BIGINT NULL`: 삭제한 회원 번호. D-103 #11의 "작성자가 지운 댓글은 복구하지 않음"을 판단한다.
   - `owner_warnings.reason VARCHAR(500) NULL`: 경고 사유. D-103 #12로 필수가 됐다.
   - 설명만 고칠 것: `admin_actions.action_type`에 BLOG_UNHIDE·POST_UNHIDE·COMMENT_UNHIDE, `notifications.notification_type` 예시에 005 종류
   - 절차:
     1. Crowfoot 문서 654의 요구사항(ADM-03, ADM-07)을 D-103에 맞춘다.
     2. `apply_schema`로 칸을 더한다.
     3. `plan_migration` 결과를 사용자에게 보인다.
     4. 승인을 받은 뒤 `apply_migration`을 한다.
     5. `export_ddl`로 `docs/04-design/schema.sql`을 다시 만든다.
   - **승인 전에 진행할 수 있는 것**: 위 두 칸에 기대는 두 부분을 빼고 모두 진행한다(tasks T001~T056).
     - 블로그장이 지운 댓글 복구: 승인 전에는 관리자가 지운 댓글만 복구된다(`admin_actions` 기록으로 판단).
     - 경고 이력의 사유 표시: 승인 전에는 사유가 활동 기록 memo와 알림에만 남는다.
     - 칸이 생기면 T057로 마무리한다.
2. **003 확인**: 003 plan이 나오면 신고 행(`reports`) 모양과 알림 이름(`OWNER_WARNED` 등)을 맞춘다(R-16). 다르면 data-model "알림 종류"와 계약을 고친다.
3. **병합 순서**: 005 브랜치는 004 위에 있다. 003 → 005 순서로 병합한다.
4. ~~**D-103 #8 확인 요청**에 답이 오면 반영한다~~ → D-104로 반영했다(위 "확인할 가정" 아래).

## 복잡도 기록 (Complexity Tracking)

헌장 위반 없음. "전체 보기" 요청 제한의 서버 메모리 사용은 001 R-08에서 이미 받아들인 예외와 같다.
