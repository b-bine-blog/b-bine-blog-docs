# 005 메인 관리자·제재 조사 (Phase 0 Research)

**날짜**: 2026-10-08 | **명세**: [spec.md](spec.md) | **계획**: [plan.md](plan.md)

명세의 확인 필요 항목 25곳(질문 21개)은 D-103으로 모두 정해졌다. 001(R-01~R-14), 002(R-01~R-17), 004(R-01~R-17)에서 정한 기술은 그대로 쓰고, 여기서는 005에서 새로 생기는 구현 방식만 정한다.
규칙 값(경고 3번, 1년, 30일, 사유 500자)은 명세·결정을 따르고 여기서 새로 정하지 않는다. "*가정*"으로 표시한 것은 문서에 없어 구현 기본값으로 둔 것이며, 사용자 확인 뒤 바뀔 수 있다. 맨 아래 "가정 모음"에 다시 모았다.

---

## R-01 이미 있는 코드 (재사용 목록)

2026-10-08 기준 `src/main/java/com/mainblog/`를 찾아본 결과다. 관리자 API(`/api/admin/**`)와 관리자 화면은 아직 하나도 없다. 사용자가 말한 "관리자 계정인데 블로그들을 관리 할 수가 없어"는 이 때문이다. 002가 서비스만 만들어 두고 "005의 관리자 API가 부른다"고 주석을 남겼다.

| 있는 것 | 위치 | 005에서 쓰는 방법 |
|---|---|---|
| 관리자 구분 role = ADMIN | `member/domain/UserRole`(USER·ADMIN), `User.isAdmin()`, `users.role` CHECK | 관리자 확인의 기준(R-02). 새 테이블 없음(D-90) |
| 요청마다 DB에서 회원 확인 | `auth/security/JwtAuthenticationFilter`가 매 요청 `userRepository.findById`로 ACTIVE를 본다. 권한(authority)은 넣지 않는다 | 같은 조회에서 role을 읽어 `ADMIN` 권한을 붙인다(R-02). 회수하면 다음 요청부터 거부(FR-002) |
| 오류 코드 `ADMIN_ONLY`(403), `ADMIN_NOT_ALLOWED`(403) | `common/error/ErrorCode` | 관리자 API를 관리자가 아닌 사람이 부르면 `ADMIN_ONLY`. 관리자의 블로그 활동 거부는 `ADMIN_NOT_ALLOWED` 그대로 |
| 관리자의 블로그 활동 거부 | `BlogService`(블로그 만들기), `JoinService`(참여 신청), `PostPolicy.requireWriter`(글쓰기), `CommentService`(댓글), `LikeService`(좋아요) | FR-004는 팔로우(003)를 빼고 이미 된다. 005는 테스트로 확인만 한다 |
| 관리자 확인 도우미 | `board/application/PostPolicy.isAdmin()`·`requireAdmin()`(공지에서 씀) | 같은 방식으로 `admin/application/AdminGuard`를 만든다. 공지 쪽은 그대로 둔다 |
| 세션 응답의 admin 값 | `SessionMemberQuery.SessionMember.admin`(`GET /api/auth/session`) | 상단 메뉴에 "관리자" 링크를 보이고, 관리자에게 "블로그 만들기·내 블로그"를 숨긴다(D-90) |
| 가리기 도구 | `common/masking/EmailMasker`(@ 앞 2글자, 2글자 이하면 1글자 + `***`), `PhoneMasker`(`010-****-5678`) | 형식이 4.4와 같아 그대로 쓴다(FR-006, D-22) |
| 블로그 숨김 칸 | `blogs.hidden`·`hidden_at`, `Blog.isHidden()` | 목록·검색·피드 제외는 이미 된다: `BlogQueryService.LISTED`, `PostVisibility`(피드·검색·태그·구독·팔로우), `OgTagRenderer`. 들어가기 막기는 아직 없다(R-07) |
| 강제 폐쇄 | `BlogClosingService.closeBySystem(blogId, CloseReason.ADMIN, actorId)`: 누른 날 + 7일 04:00, 즉시 알림, 위임 요청 자동 취소. 문구 "운영 정책에 따른 폐쇄 조치". 철회 `withdraw`는 블로그장만, 관리자 폐쇄(`ADMIN`)는 막음(D-104) | 그대로 부른다(FR-013, D-94). 이미 폐쇄 예정이면 지금은 `BLOG_ALREADY_CLOSING`을 던지므로 D-103 #8용 메서드를 더한다(R-08) |
| 블로그장 박탈 후 처리 | `OwnerSuccessionService.revokeOwner(blogId, adminId)`: 박탈된 사람은 MEMBER로, 가장 먼저 된 부블로그장(`manager_since`, id 순)을 OWNER로. 없으면 `OWNER_REVOKED` 폐쇄 예약. 이미 폐쇄 예정이면 기존 시각 유지. 개수 제한 확인 없음 | D-103 #14·#16·#17과 같다. 위임 요청 자동 취소 알림(#15)만 더한다(R-09) |
| 폐쇄 알림 중복 방지 | `blog_closing_notices` 유니크 + `event_key` + 04:00 `sendDueNotices` | 그대로(SC-006) |
| 블로그 안 신고 처리 | `BlogReportService`: `route = 'BLOG'`만 다룬다. 결과 NONE·WARNING·SUSPEND·KICK, 신고자 보호(`reporterId` 응답 제외), `REPORT_ALREADY_HANDLED`, `REPORT_RESOLVED` 알림 | 관리자 신고 처리(`route = 'ADMIN'`)를 같은 모양으로 만든다(R-10). 블로그장 신고함에 관리자 신고가 안 보이는 것(SC-007 앞부분)은 이미 된다 |
| 블로그 단위 제재 | `SanctionService`, `SuspensionQuery`, `BlacklistService`, `blog_sanctions`(정지 3일·14일·30일·영구) | FR-035~FR-037은 002로 이미 된다. 1년 정리에서 "아직 효력 있는 정지"를 고를 때 `SuspensionQuery`를 쓴다(R-13) |
| 알림 쓰기 | `common/notification/NotificationWriter`(설정 확인, `INSERT IGNORE` + `event_key`), `NotificationType`(tab·설정 칼럼) | 종류 5개를 더한다(data-model "알림 종류"). `REPORT_RESOLVED`, `DELEGATION_CANCELED`, `BLOG_CLOSING`, `POST_DELETED`는 이미 있다 |
| 글·댓글 상태 | `posts.status`(VISIBLE·HIDDEN·DELETED), `posts.hidden_at`, `deleted_at`, `deleted_by`. `comments.status`(같은 세 값), `deleted_at`. 004는 HIDDEN을 쓰지 않고 VISIBLE만 보여 준다 | 숨김·삭제·복구를 이 칸으로 한다(R-11). `comments`에는 `deleted_by`가 없다(R-15) |
| 글 삭제와 알림 | `PostService.delete`: 작성자·POST_MANAGE·관리자, 남이 지우면 `POST_DELETED`(`event_key = POST_DELETED:{postId}`) | 관리자 삭제는 활동 기록을 남기도록 005 서비스로 보낸다(R-11) |
| 글 이미지 | `images`(owner_type POST). 글을 지워도 이미지는 글이 30일 정리될 때 `deleted_at`이 채워진다 | 30일 안에 글을 복구하면 사진도 그대로 돌아온다(FR-019 "사진") |
| 04:00 정리 | `batch/DailyCleanupJob`(`@Scheduled` + ShedLock `dailyCleanup`), `BlogDailyTasks`, `BoardDailyTasks`(삭제 30일 글·댓글 정리) | `AdminDailyTasks`(운영 기록 1년 정리)를 단계로 더한다(R-13) |
| 요청 제한 | `common/ratelimit/RateLimiter`(서버 메모리, 001 R-08), 429 `RATE_LIMITED` | "전체 보기" 요청 제한에 쓴다(R-04) |
| 화면 공통 | `static/js/layout.js`(상단 메뉴, textContent), `api.js`(X-XSRF-TOKEN, 5초 중단), `session.js`, `css/base.css` | 관리자 화면도 같은 틀을 쓴다(R-03) |
| 테스트 부품 | `support/IntegrationTestBase`, `AuthTestSupport`, `MutableClock`, `blog/BlogTestBase`, `board/BoardTestBase`, `contract/OpenApiConformanceTest` | `admin/AdminTestBase`를 `BoardTestBase` 위에 둔다. 신고 행은 003 API 없이 직접 넣는다 |
| 시드 관리자 | `local/seed.sql`의 `admin@local.test`(id 104, role ADMIN) | quickstart 화면 확인에 쓴다 |

**이미 충족된 FR**(005에서 테스트로 확인만 함):
- FR-004: 블로그 만들기·참여 신청·글쓰기·댓글·좋아요 거부. 팔로우 거부는 003 FR-006에서 붙는다
- FR-010: 관리자용 회원 정지·강제 탈퇴·멤버 제재 API가 없다
- FR-014: 폐쇄 30일 뒤 정리(002 `BlogPurgeService`)
- FR-016: 남의 글 수정 거부(004 `PostPolicy.canEdit`)
- FR-025: 폐쇄 예정 중에도 글쓰기·댓글(002·004)
- FR-035~FR-037: 블로그 단위 제재(002)

**일부만 된 FR**: FR-012(목록·검색·피드 제외만 됨), FR-013(서비스만 있음), FR-017(관리자 삭제 알림은 되지만 활동 기록 없음), FR-019(30일 정리만 됨), FR-023·FR-024·FR-026(서비스만 있음), FR-029(위임 요청 취소 알림 없음), FR-033(알림 종류만 있음), FR-038(1년 전에 지우지는 않지만 1년 뒤 정리가 없음).

## R-02 관리자 확인 (매 요청 서버에서)

- **결정**:
  - `JwtAuthenticationFilter`가 이미 매 요청 DB에서 읽는 `User`의 role이 ADMIN이면 `SimpleGrantedAuthority("ADMIN")`을 붙인다. 토큰에는 지금처럼 회원 번호만 있다.
  - `SecurityConfig`에 `.requestMatchers("/api/admin/**").hasAuthority("ADMIN")`를 `/api/**` 앞에 둔다. 로그인하지 않았으면 기존 진입점이 401 `UNAUTHENTICATED`, 로그인했지만 관리자가 아니면 새 `AccessDeniedHandler`가 403 `ADMIN_ONLY`를 JSON으로 준다. CSRF 거부(`CsrfException`)는 지금처럼 403이다.
  - 서비스에서도 `AdminGuard.require(userId)`로 한 번 더 확인한다(004 `PostPolicy.requireAdmin`과 같은 방식). 주소 규칙을 실수로 빼도 막히게 하기 위해서다.
  - 거부 응답에는 코드와 메시지만 있다. 회원 정보나 가입 여부는 담지 않는다(FR-003, D-28).
- **이유**: SEC-09, SEC-11(주소 단위로 비회원·회원·관리자를 나눔), 헌장 II(토큰만 믿지 않음). role을 USER로 되돌리면 다음 요청의 필터 조회에서 권한이 빠진다(FR-002, D-103 #1).
- **검토한 다른 안**: 토큰에 role 넣기(헌장 II 위반, 회수가 바로 반영되지 않음), 서비스 확인만 하기(주소 단위 확인 SEC-11을 못 지킴).

## R-03 관리자 화면 `/admin`

- **결정**:
  - 화면 HTML은 `static` 밖(`src/main/resources/admin/index.html`)에 두고 `AdminPageController`가 `GET /admin`, `/admin/**`에서 role을 확인한 뒤 내려준다. 비로그인은 `/login.html`로 보내고, 관리자가 아니면 404 화면이다. *가정*: 관리자 페이지가 있는지 드러내지 않으려고 403 대신 404로 한다.
  - 한 화면에 탭 6개: 회원, 블로그, 신고, 글·댓글, 활동 기록, 통계. 스크립트는 `static/js/admin-*.js`(데이터 없음, 누구나 받아도 됨)이고 모든 값은 `textContent`로 넣는다. 관리자 화면에는 글 본문도 HTML로 넣지 않는다. 본문은 서버가 거른 `contentHtml`이 있지만 관리자 화면에서는 글자만 보여 준다(D-64보다 엄격하게).
  - `layout.js`: 세션의 `admin`이 true면 "관리자" 링크를 보이고 "블로그 만들기·내 블로그"를 숨긴다(D-90).
  - PC·모바일 모두 쓸 수 있게 `base.css`의 반응형 틀을 쓰고, 표는 좁은 화면에서 카드 목록으로 바꾼다(SC-010).
- **이유**: D-103 #1(관리자 페이지는 `/admin`, role = ADMIN만 들어감), D-66(정적 HTML + JS).

## R-04 회원 조회와 "전체 보기"

- **검색** (`GET /api/admin/members`):
  - `type=NICKNAME`: 닉네임 일부 일치(`LIKE`, `%`·`_`는 이스케이프), 1~12자
  - `type=EMAIL`: 소문자로 바꿔 전체 일치(`uk_users_email`)
  - 이름·전화번호 검색은 없다(D-103 #2)
  - 탈퇴한 회원은 빼고(D-103 #3), 관리자 계정도 뺀다. *가정*
  - 최근 가입 순 번호 페이지
- **목록 응답**: 회원 번호, 닉네임, 이름, 가린 이메일, 가입일. 목록에는 전화번호와 "전체 보기"가 없다(D-103 #5).
- **상세 응답** (`GET /api/admin/members/{userId}`): 가린 이메일·가린 전화번호, 이름(가리지 않음, D-103 #4), 닉네임, 가입일, 상태, 운영·참여 블로그(공개 범위와 관계없이, 역할 포함), 블로그장 경고 이력(블로그별 1년 안 경고 수와 기록). 비밀번호 칸은 없다(FR-009). 탈퇴한 회원은 404 `NOT_FOUND`. *가정*
- **"전체 보기"** (`POST /api/admin/members/{userId}/privacy-view`):
  - 원래 이메일과 전화번호(`010-1234-5678` 형식)를 돌려준다.
  - 같은 트랜잭션에서 `admin_actions`에 `PRIVACY_VIEW`(대상 USER)를 쓴다. 기록이 실패하면 값도 주지 않는다.
  - 사유는 받지 않는다(D-103 #5).
  - 응답에 `Cache-Control: no-store`를 붙인다. 화면은 그 상세 화면에서만 값을 보여 주고, 다시 열면 상세 API를 새로 불러 가린 값으로 돌아간다.
  - POST인 이유: 기록을 남기는 요청이라 CSRF를 검사하고, 브라우저·프록시 캐시에 남지 않게 하기 위해서다.
  - 관리자 한 명당 1분에 30번(`admin.privacy-view.rate-limit`, *가정*)을 넘으면 429 `RATE_LIMITED`. 개인정보를 한꺼번에 긁어 가는 것을 막는다.
- **로그**: 원래 이메일·전화번호는 로그에 쓰지 않는다. `AdminSecurityTest`가 확인한다.
- **이유**: FR-005~FR-009, 4.4 메인 관리자 행, D-22(서버에서 가림), D-103 #2~#5.

## R-05 블로그 조회

- **검색** (`GET /api/admin/blogs`):
  - `q`는 이름·주소·블로그장 닉네임 중 하나라도 일부 일치하면 찾는다(`LIKE`). *가정*: 세 항목 모두 일부 일치로 했다.
  - `status`: `ACTIVE`, `CLOSING`, `CLOSED`, `HIDDEN`(숨김만), 비우면 모두
  - 공개 범위와 관계없이 보여 준다(D-103 #6). 폐쇄된 블로그는 30일 정리 전(`closed_at`이 `blog.closing.purge-after` 안)까지만 나온다. 정리된 블로그는 주소가 비어 있어 찾을 수 없기 때문이다.
  - 최근 생성 순 번호 페이지
- **응답**: 블로그 번호, 이름, 주소, 공개 범위, 상태, 숨김 여부, 폐쇄 예정 시각·사유, 블로그장(닉네임, 없으면 null), 멤버 수(`member_count`), 글 수(삭제되지 않은 블로그 글: VISIBLE + HIDDEN). *가정*: 숨긴 글은 아직 있는 글이라 센다.
- **상세** (`GET /api/admin/blogs/{blogId}`): 위 항목에 더해 지금 블로그장의 1년 안 경고 수, 부블로그장 목록(닉네임, 된 시각), 대기 중인 위임 요청 여부.
- **이유**: FR-011, ADM-02, D-103 #6.

## R-06 관리자 활동 기록 (`admin_actions`)

- **쓰기**: `AdminActionLog.write(adminId, actionType, targetType, targetId, reportId, memo)`. 조치와 같은 트랜잭션에서 쓴다. 조치가 되돌려지면 기록도 남지 않고, 기록이 실패하면 조치도 되돌린다(SC-004).
- **종류** (`action_type`, VARCHAR(30), CHECK 없음): 스키마 설명의 13개에 숨김 해제 3개를 더한다(설명 문구만 바뀜, R-15).

| action_type | target_type | 언제 | memo |
|---|---|---|---|
| OWNER_WARNING | USER(블로그장) | 블로그장 경고 | `블로그 {번호}: {사유}` |
| OWNER_KICK | USER | 바로 강퇴, 경고 3번 박탈 | `블로그 {번호}: 바로 강퇴` 또는 `경고 3번` + 사유(있으면) |
| AUTO_DELEGATE | BLOG | 박탈 뒤 부블로그장에게 넘김 | `새 블로그장 회원 {번호}` |
| CLOSE_SCHEDULE | BLOG | 박탈 뒤 폐쇄 예약(또는 기존 예정 유지) | 폐쇄 예정 시각 |
| BLOG_HIDE / BLOG_UNHIDE | BLOG | 숨김·숨김 해제 | |
| BLOG_FORCE_CLOSE | BLOG | 강제 폐쇄 | 폐쇄 예정 시각, 기존 예정 유지면 그 표시 |
| POST_HIDE / POST_UNHIDE / POST_DELETE | POST | 글 숨김·해제·삭제 | |
| COMMENT_HIDE / COMMENT_UNHIDE / COMMENT_DELETE | COMMENT | 댓글 숨김·해제·삭제 | |
| RESTORE | POST·COMMENT | 복구 | |
| REPORT_HANDLE | REPORT | 신고 처리 | 처리 결과 |
| PRIVACY_VIEW | USER | "전체 보기" | |

- 신고 처리로 생긴 조치(경고·강퇴·폐쇄)는 그 행에도 `report_id`를 채운다.
- memo에는 원래 이메일·전화번호를 넣지 않는다.
- **보기** (`GET /api/admin/actions`): 모든 관리자가 본다(D-103 #20). 거르기: 종류, 관리자, 대상(종류 + 번호), 기간(날짜). 최신순 번호 페이지(`idx_admin_actions_created_at`). 응답에는 관리자 닉네임과 대상 이름(회원 닉네임·블로그 이름·글 제목, 탈퇴 회원은 "탈퇴한 회원", 지워진 대상은 "삭제된 대상")을 함께 준다.
- **고치기·지우기 API는 만들지 않는다**(D-103 #20). 지우는 것은 1년 정리뿐이다(R-13).
- **이유**: FR-039, ADM-06, SEC-09, 4.4.

## R-07 블로그 숨김

- **숨김** (`PUT /api/admin/blogs/{blogId}/hidden`): `hidden = TRUE`, `hidden_at = 지금`. 블로그장에게 `BLOG_HIDDEN` 알림(끌 수 없음, 멤버에게는 보내지 않음), `BLOG_HIDE` 기록(D-103 #7).
- **해제** (`DELETE` 같은 주소): `hidden = FALSE`, `hidden_at = NULL`, `BLOG_UNHIDE` 기록. *가정*: 해제 알림은 D-103 #7에 없어 보내지 않는다.
- 이미 숨김이면 409 `ALREADY_HIDDEN`, 숨김이 아니면 409 `NOT_HIDDEN`, 폐쇄된 블로그는 409 `BLOG_ALREADY_CLOSED`. 폐쇄 예정인 블로그도 숨길 수 있다.
- **들어가기 막기**: 002 `BlogAccessPolicy.canView`의 맨 앞에서 `blog.isHidden()`이고 멤버가 아니면 false로 한다. 그러면 블로그 홈·글 목록·글 상세·공유 링크·구독자 접근이 모두 002·004의 기존 "볼 수 없음" 처리(404)로 막힌다. 블로그장·멤버는 그대로 보고 쓴다.
  - 관리자도 멤버가 아니므로 일반 화면으로는 숨긴 블로그를 볼 수 없다. 관리자는 관리자 화면(R-11의 글 목록)으로 본다.
- 목록·검색·피드 제외는 이미 된다(R-01).
- **이유**: FR-012, ADM-02, 6.1, D-103 #7.

## R-08 강제 폐쇄

- **결정** (`POST /api/admin/blogs/{blogId}/force-close`):
  - 운영 중이면 `BlogClosingService.closeBySystem(blogId, ADMIN, adminId)`: 누른 날 + 7일 04:00, 블로그장을 뺀 멤버·구독자에게 즉시 알림, 3일 전·1일 전은 04:00 처리가 보낸다(FR-013, D-94).
  - 이미 폐쇄 예정이면 `BlogClosingService.markAdminClose(blogId)`(새 메서드)로 `close_reason`만 `ADMIN`으로 바꾸고 시각과 알림은 그대로 둔다(D-103 #8). 그 뒤 3일 전·1일 전 알림 문구는 "운영 정책에 따른 폐쇄 조치"가 된다.
  - 폐쇄된 블로그는 409 `BLOG_ALREADY_CLOSED`.
  - `BLOG_FORCE_CLOSE` 기록, 응답은 폐쇄 예정 시각과 "기존 예정 유지" 여부.
- **철회**(D-104로 바뀜): 002 `ClosingController`의 철회는 블로그장만 할 수 있고, 사유가 `ADMIN`이면 403 `ADMIN_CLOSE_LOCKED`로 막는다. 관리자 폐쇄는 관리자 API `DELETE /api/admin/blogs/{blogId}/force-close`로만 철회한다(`BlogClosingService.withdrawByAdmin`, 같은 철회 알림, `RESTORE`·`BLOG` 기록, memo "강제 폐쇄 철회"). 사유가 `ADMIN`이 아니면 409 `NOT_ADMIN_CLOSE`. 관리자가 블로그장 철회 API를 부르면 002가 `BLOG_FORBIDDEN`으로 막는다.
- **이유**: FR-013, FR-031, ADM-02, D-94, D-103 #8, D-104.

## R-09 블로그장 경고와 권한 박탈

- **경고** (`POST /api/admin/blogs/{blogId}/owner-warnings`, 본문 `ownerId`, `reason`):
  1. 블로그 행을 잠근다(`findByIdForUpdate`). 폐쇄됐으면 409 `BLOG_ALREADY_CLOSED`.
  2. 지금 블로그장이 `ownerId`가 아니면(블로그장이 바뀌었거나 박탈되어 없음) 409 `OWNER_CHANGED`. 두 관리자가 동시에 경고해도 박탈 뒤 새 블로그장이 대신 경고를 받지 않게 하기 위해서다(SC-005).
  3. 사유는 앞뒤 공백 제거 후 1~500자(`admin.warning.reason-max-length`, D-103 #12), 아니면 400 `VALIDATION_FAILED`.
  4. `owner_warnings`에 넣는다(사유는 R-15 승인 뒤 `reason` 칸에도). `OWNER_WARNING` 기록.
  5. 그 블로그·그 회원의 1년(`admin.warning.window`) 안 경고 수를 센다(D-95, D-103 #13). 블로그장이 바뀌면 새 사람은 자기 경고만 세므로 0부터다.
  6. 블로그장에게 `OWNER_WARNED` 알림: "'{블로그}' 블로그장 경고 (3번 중 {n}번). 사유: {사유}". 신고자는 넣지 않는다(D-103 #12).
  7. 경고 수가 `admin.warning.revoke-threshold`(3) 이상이면 같은 트랜잭션에서 박탈한다(원인 `WARNING_3`).
- **바로 강퇴** (`POST /api/admin/blogs/{blogId}/owner-revocation`, 본문 `ownerId`, `reason`(선택)): 1·2단계 뒤 박탈한다(원인 `DIRECT_KICK`). *가정*: 강퇴 사유는 문서에 없어 선택(0~500자)으로 두고 기록 memo와 알림에 넣는다.
- **박탈** (`OwnerRevocationService.revoke`, 블로그 행 잠금 안에서 한 번에):
  1. 대기 중인 위임 요청(`blog_delegations.status = 'PENDING'`)을 `AUTO_CANCELED`로 바꾸고, 받는 멤버에게 `DELEGATION_CANCELED` 알림 "위임 요청이 취소되었습니다"(끌 수 없음, `event_key = DELEGATION_CANCELED:{id}`)를 보낸다(D-103 #15).
  2. `OwnerSuccessionService.revokeOwner`를 부른다. 부블로그장이 있으면 가장 먼저 된 사람이 블로그장이 되고(수락 없음, 개수 제한 없음, D-103 #16), 없으면 `OWNER_REVOKED` 폐쇄 예약(문구 "블로그장 권한 박탈로 인한 폐쇄 조치", D-103 #17). 이미 폐쇄 예정이면 기존 시각을 그대로 둔다(D-103 #14).
  3. `owner_revocations`에 원인·새 블로그장·폐쇄 예정 시각을 넣는다.
     - **박탈된 사람은 폐쇄 예정 알림에서 뺀다**(US3-5 "P를 제외한 멤버 전원", FR-024).
     - 지금 002 구현은 박탈된 사람을 MEMBER로 바꾼 뒤 알림 대상을 계산해서, 그 사람도 즉시·3일 전·1일 전 알림을 받는다.
     - 그래서 `BlogClosingService.closeBySystem`에 뺄 회원(박탈된 사람)을 넘겨 즉시 알림에서 뺀다.
     - 3일 전·1일 전 알림 대상 쿼리에는 "`owner_revocations`에서 이 블로그·이 폐쇄 예정 시각의 `user_id`"를 빼는 조건을 더한다. 블로그장이 이미 폐쇄를 눌러 둔 블로그도 박탈 기록에 기존 시각이 들어가므로 같은 조건으로 빠진다.
  4. 박탈된 사람에게 `OWNER_REVOKED` 알림(끌 수 없음, FR-027).
  5. `OWNER_KICK`과 `AUTO_DELEGATE` 또는 `CLOSE_SCHEDULE`을 기록한다(FR-039).
  - *가정*: 새 블로그장에게 따로 알림을 보내지 않는다. 3.6 표에 없는 알림이라서다.
- **동시성**: 모든 경고·박탈·신고 처리는 블로그 행 잠금으로 줄을 세운다. 2단계의 `ownerId` 확인 덕분에 박탈·위임·폐쇄 예약은 블로그당 한 번만 일어난다(FR-028, SC-005).
- **경계**: 메인 관리자는 블로그장이 아닌 멤버를 경고·정지·강제 퇴장하는 API가 없다(FR-010). 박탈된 사람을 어떻게 할지는 새 블로그장이 002 제재로 정한다(FR-026).
- **이유**: FR-020~FR-029, ADM-07, D-17, D-30, D-44, D-54, D-94, D-95, D-103 #12~#17.

## R-10 블로그·블로그장 신고 처리

- **대상**: 003이 만드는 `reports` 행 가운데 `route = 'ADMIN'`(D-93). 블로그 자체, 블로그장, 블로그장이 자기 블로그에 쓴 글·댓글, 메인 프로필 회원 신고다. 어떤 신고가 ADMIN으로 가는지는 003이 만들 때 정하고, 005는 `route`만 믿는다.
- **신고함** (`GET /api/admin/reports?status=PENDING|DONE`): 대기 중은 오래된 순(먼저 온 것부터 처리), 처리됨은 최근 처리 순이다. *가정*. 인덱스 `idx_reports_route_status_created_at`.
- **상세** (`GET /api/admin/reports/{reportId}`):
  - 대상 종류·번호, 신고 당시 내용(`target_snapshot`, D-85), 사유·추가 설명(D-102 #14), 접수 시각, 처리 결과
  - 대상 블로그(이름·상태), 처리 대상이 될 블로그장(닉네임)
  - 신고자 닉네임: 메인 관리자만 허위 신고 확인을 위해 본다(D-102 #15). 탈퇴했으면 "탈퇴한 회원"(D-102 #16, D-103 #3)
- **처리** (`POST /api/admin/reports/{reportId}/resolution`, 본문 `result`, `reason`):
  1. 신고를 읽고(잠그지 않음) 블로그가 있으면 블로그 행 → 신고 행 순서로 잠근다(교착 방지). 이미 `DONE`이면 409 `REPORT_ALREADY_HANDLED`(FR-034).
  2. `result`
     - `NONE`: 조치 없음
     - `OWNER_WARNING`: 사유 필수. 처리 대상 블로그장에게 R-09 경고
     - `OWNER_KICK`: R-09 바로 강퇴
     - `BLOG_CLOSE`: R-08 강제 폐쇄
  3. 처리 대상 블로그장
     - BLOG 신고: 지금 블로그장
     - USER 신고(블로그 있음): `target_id`
     - POST·COMMENT 신고: 그 글·댓글 작성자
     - 그 사람이 지금 블로그장이 아니면 409 `OWNER_CHANGED`. 관리자는 "문제 없음"으로 닫거나 블로그 화면에서 따로 조치한다.
  4. 블로그가 없는 신고(메인 프로필 회원 신고, `blog_id IS NULL`)는 `NONE`만 받는다. 나머지는 400 `VALIDATION_FAILED`. *가정*: 관리자 조치는 블로그장·블로그 단위뿐이라서다(D-44).
  5. `reports`를 `status = 'DONE'`, `result`, `handled_by`, `handled_at`으로 바꾸고 `REPORT_HANDLE`을 기록한다. 조치 기록과 `owner_warnings.report_id`에 신고 번호를 채운다.
  6. 신고자에게 `REPORT_RESOLVED` 알림("신고가 처리되었습니다. 결과: 블로그장 경고"). 신고자가 "신고 처리 결과"를 껐으면 만들지 않는다(`report_result` 설정, FR-033).
- 신고 수로 자동 조치하는 코드는 없다(FR-032).
- 처리 결과는 바꿀 수 없다. 같은 대상의 새 신고는 따로 처리한다(D-103 #18).
- **이유**: FR-030~FR-034, ADM-04, D-45, D-85, D-93, D-102 #14~#16, D-103 #18.

## R-11 글·댓글 숨김·삭제·복구

- **관리자 글 보기**:
  - `GET /api/admin/posts`: 블로그 번호·제목 일부·상태(`VISIBLE`·`HIDDEN`·`DELETED`)로 거른다. 공개 범위·숨김과 관계없이 보여 주고, 삭제 글은 30일 안의 것만 나온다.
  - `GET /api/admin/posts/{postId}`: 본문 원문·작성자 닉네임·상태·삭제한 사람(작성자·블로그장·관리자)·복구 가능 여부를 준다.
  - *가정*: ADM-03("어느 블로그의 글이든")을 판단하려면 비공개·숨김 블로그의 글도 봐야 해서 관리자 화면에서는 볼 수 있게 했다.
  - 댓글: `GET /api/admin/comments?postId=&status=`
- **글 숨김** (`PUT /api/admin/posts/{postId}/hidden`):
  - VISIBLE → HIDDEN, `hidden_at = 지금`, `POST_HIDE` 기록
  - 작성자에게 `POST_HIDDEN` 알림 "내 글 숨겨짐"(끌 수 없음, `event_key = POST_HIDDEN:{postId}:{숨긴 시각}`, D-103 #9)
  - 블로그 글만 받는다. 공지는 004의 관리자 수정·삭제로 관리한다. *가정*
- **숨김 해제** (`DELETE` 같은 주소): HIDDEN → VISIBLE, `hidden_at = NULL`, `POST_UNHIDE` 기록, 알림 없음.
- **숨긴 글 보이기**(004 고침):
  - 글 상세는 작성자 본인에게만 `hiddenByAdmin: true`와 함께 내려준다. 블로그장·다른 사람에게는 404 `POST_NOT_FOUND`(D-103 #10).
  - 작성자는 볼 수 있고 지울 수 있지만, 고치기·댓글·좋아요·공유는 막는다. *가정*
  - 목록·검색·피드는 지금처럼 VISIBLE만 보여 준다. *가정*: 작성자 본인 목록에도 넣지 않고 링크로만 본다.
- **글 삭제** (`DELETE /api/admin/posts/{postId}`):
  - VISIBLE·HIDDEN → DELETED, `deleted_at`, `deleted_by = 관리자`, `POST_DELETE` 기록
  - 작성자에게 `POST_DELETED`(004와 같은 문구)
  - `event_key`를 `POST_DELETED:{postId}:{삭제 시각}`으로 바꿔, 복구한 뒤 다시 지워도 알림이 다시 가게 한다(004 `PostService`도 같은 키로 맞춘다).
  - 004의 `DELETE /api/posts/{postId}`를 관리자가 부르면 같은 005 서비스로 보내 활동 기록이 빠지지 않게 한다.
- **댓글 숨김·해제·삭제** (`/api/admin/comments/{commentId}/hidden`, `DELETE /api/admin/comments/{commentId}`): 상태만 바꾸고 기록한다. 작성자에게 알리지 않는다(D-103 #9). 삭제는 `deleted_at`(+ R-15 승인 뒤 `deleted_by`)을 채운다.
- **숨긴 댓글 보이기**(004 고침): 숨긴 댓글은 응답에서 뺀다. 답글이 남은 최상위 댓글을 숨기면 "관리자가 숨긴 댓글입니다" 자리(`hidden: true`, 내용·작성자 없음)로 남겨 답글이 사라지지 않게 한다. *가정*: D-100 #3의 "삭제된 댓글입니다"와 같은 방식이다.
- **복구** (`POST /api/admin/posts/{postId}/restore`, `.../comments/{commentId}/restore`):

| 조건 | 결과 |
|---|---|
| 상태가 DELETED가 아님 | 409 `NOT_RESTORABLE` |
| 30일이 지나 행이 지워짐 | 404 `POST_NOT_FOUND`·`COMMENT_NOT_FOUND` |
| 작성자가 스스로 지움(`deleted_by = author_id`) | 409 `NOT_RESTORABLE`(D-103 #11) |
| 블로그가 폐쇄됨 | 409 `BLOG_ALREADY_CLOSED`. *가정* |
| 그 밖(관리자·블로그장이 지움, 30일 안) | 글: `hidden_at`이 있으면 HIDDEN, 없으면 VISIBLE로. `deleted_at`·`deleted_by`를 비운다. 작성자에게 `POST_RESTORED` 알림. 댓글: VISIBLE로, 알림 없음. `RESTORE` 기록 |

  - 댓글의 "누가 지웠나"는 `comments.deleted_by`가 생기기 전(R-15)까지 `admin_actions`의 `COMMENT_DELETE` 기록으로 판단한다. 그래서 그 전에는 관리자가 지운 댓글만 복구된다.
  - *가정*: 댓글은 숨김 시각 칸이 없어, 숨긴 뒤 지운 댓글을 복구하면 보이는 상태로 돌아간다.
  - 사진: 글 이미지는 글이 30일 정리될 때만 `deleted_at`이 채워지므로, 30일 안에 글을 복구하면 사진도 그대로 보인다.
- 남의 글을 고치는 API는 없다(FR-016).
- **이유**: FR-015~FR-019, ADM-03, 4.5, D-07, D-58, D-103 #9~#11.

## R-12 통계

- **결정** (`GET /api/admin/stats`): 한 번에 다음을 준다(D-103 #21). 날짜는 한국 시간 `Clock` 기준이다.
  - 회원 수: `users.status = 'ACTIVE' AND role = 'USER'`
  - 블로그 수: `blogs.status IN ('ACTIVE','CLOSING')`(숨김 포함)
  - 일별 가입 수: 오늘 포함 최근 30일(`admin.stats.daily-days`), `users.role = 'USER'`인 행을 `DATE(created_at)`로 센다. 나중에 탈퇴한 회원도 행이 남아 있어 그대로 센다.
  - 일별 글 수: 같은 기간 `posts.board_type = 'BLOG'`(상태와 관계없이). 삭제 글은 30일 뒤 행이 지워지지만, 일별 기간이 30일이라 셀 수 있다. *가정*: 공지는 관리자가 쓰는 글이라 뺀다.
  - 글이나 가입이 없는 날은 0으로 채운다.
- **이유**: FR-040, ADM-05, D-103 #21. 일별 범위를 30일보다 늘리면 지워진 글이 빠지므로 설정값 설명에 적어 둔다.

## R-13 운영 기록 1년 정리 (04:00)

- **결정**: `admin/application/AdminDailyTasks`를 `DailyCleanupJob`(ShedLock `dailyCleanup`)의 마지막 단계로 더한다. 기준은 기록이 생긴 날 + 1년(`admin.records.retention`, D-103 #19)이고, 단계마다 트랜잭션을 따로 쓴다.
  1. `admin_actions`: `created_at`이 기준 이전인 행
  2. `owner_warnings`, `owner_revocations`: 같은 기준
  3. `blog_sanctions`: 같은 기준. 다만 아래 행은 남긴다.
     - 아직 효력이 있는 정지: 영구 정지이고 그 뒤 정지 해제가 없는 행(`SuspensionQuery`)
     - 블랙리스트(`blog_blacklists.sanction_id`)가 가리키는 강제 퇴장 행. 블랙리스트는 해시로 보관하기 때문이다(4.5).
  4. `reports`: 같은 기준. 지우기 전에 남는 행(1~3단계에서 남은 것)의 `report_id`를 NULL로 바꿔 외래 키를 푼다.
- 탈퇴한 회원의 기록은 회원 번호만 남고(001이 30일 뒤 개인정보를 비움), 화면은 "탈퇴한 회원"으로 보인다. 신고 당시 내용(`target_snapshot`)은 그대로 1년 보관한다(D-103 #19).
- 30일 정리(001·002·004)는 이 표들을 건드리지 않으므로 1년 전에 지워지지 않는다(SC-004).
- **이유**: FR-038, 4.5, D-60, D-95, D-103 #19·#20, SCL-03.

## R-14 오류 코드

- **그대로 쓰는 것**:
  - 400 `VALIDATION_FAILED`
  - 401 `UNAUTHENTICATED`
  - 403 `ADMIN_ONLY`
  - 404 `NOT_FOUND`(회원·신고), `BLOG_NOT_FOUND`, `POST_NOT_FOUND`, `COMMENT_NOT_FOUND`
  - 409 `REPORT_ALREADY_HANDLED`
  - 429 `RATE_LIMITED`
- **새로 더하는 것**(모두 409): `OWNER_CHANGED`(지금 블로그장이 요청한 대상이 아님), `ALREADY_HIDDEN`, `NOT_HIDDEN`, `NOT_RESTORABLE`(지운 상태가 아니거나 작성자가 지움), `BLOG_ALREADY_CLOSED`(폐쇄된 블로그에 숨김·폐쇄·경고·복구), `NOT_ADMIN_CLOSE`(관리자 폐쇄가 아닌 폐쇄 예정을 관리자가 철회, D-104). 403 `ADMIN_CLOSE_LOCKED`(블로그장이 관리자 폐쇄를 철회, D-104). 002의 `BLOG_ALREADY_CLOSING`은 강제 폐쇄에서 쓰지 않는다(D-103 #8로 기존 예정을 유지).

## R-15 스키마 확인과 DB 변경

- 005가 쓰는 테이블은 Crowfoot 문서 654에서 배포한 스키마(`docs/04-design/schema.sql`, 문서 버전 41)에 대부분 있다.
  - 관리자 전용 테이블: `admin_actions`(관리자 활동 기록), `owner_warnings`, `owner_revocations`
  - 관리자 칸: `blogs.hidden`·`hidden_at`·`close_reason`(ADMIN), `posts.hidden_at`·`deleted_by`, `reports.route`·`result`(OWNER_WARNING·OWNER_KICK·BLOG_CLOSE)
  - 인덱스: `idx_admin_actions_created_at`, `idx_admin_actions_target_type_target_id`, `idx_owner_warnings_blog_id_created_at`, `idx_reports_route_status_created_at`
- **구조 변경이 필요한 것 2개**(둘 다 NULL 허용 칸 추가, 지우는 문장 없음):
  1. `comments.deleted_by BIGINT NULL`(삭제한 회원 번호, users.id, FK 선 없음): D-103 #11의 "작성자가 스스로 지운 댓글은 복구하지 않음"을 판단할 칸이 댓글에는 없다. 블로그장이 지운 댓글은 `admin_actions`에도 남지 않아 다른 방법이 없다.
  2. `owner_warnings.reason VARCHAR(500) NULL`(경고 사유): D-103 #12로 사유가 필수가 됐는데 칸이 없다. 사유는 활동 기록 memo에도 남지만, 회원 상세의 "블로그장 경고 이력(블로그별)"에 사유를 보이려면 경고 행에 있어야 한다.
- **설명만 바뀌는 것**(구조 변경 없음):
  - `admin_actions.action_type` 설명에 BLOG_UNHIDE, POST_UNHIDE, COMMENT_UNHIDE를 더한다(CHECK가 없어 칸은 그대로다).
  - `notifications.notification_type` 예시에 005 종류를 더한다.
- **절차**: Crowfoot 문서 654에서 요구사항(ADM-03·ADM-07)을 고치고 `apply_schema`로 두 칸을 더한다. 그다음 `plan_migration`으로 계획을 사용자에게 보이고, 승인을 받은 뒤 `apply_migration`을 한다. 끝나면 `export_ddl`로 `schema.sql`을 다시 만든다. 이번 계획 작업에서는 Crowfoot 도구를 부르지 않았다.
- **승인 전에 할 수 있는 것**: 두 칸에 기대는 두 부분(블로그장이 지운 댓글 복구, 경고 이력의 사유 표시)을 빼고 모두 진행한다. 승인 전에는 다음처럼 둔다.
  - 댓글 복구는 `admin_actions`의 `COMMENT_DELETE`로 관리자가 지운 댓글만 판단한다.
  - 경고 사유는 활동 기록 memo와 알림에만 남는다.
  - 칸이 생기면 tasks의 T057로 바꾼다.
- **이유**: 헌장 V(명세가 먼저), CLAUDE.md(DB 원천은 Crowfoot 문서 654).

## R-16 003과의 연결

003(소셜·알림)은 005보다 먼저 구현되지만, 이 작업 시점에 이 저장소에는 003의 `spec.md`·`clarify-questions.md`만 있고 plan·data-model은 없다. 그래서 아래는 003 명세와 D-102를 기준으로 한 가정이다.

| 005가 쓰는 003의 것 | 003 근거 | 005에서 |
|---|---|---|
| `reports` 행 만들기(접수처 `route`, 대상 종류·번호, `blog_id`, `target_snapshot`, 사유·추가 설명) | 003 FR-022~FR-027, D-93, D-85, D-102 #14 | `route = 'ADMIN'`만 읽고 처리한다. 테스트는 행을 직접 넣는다 |
| 신고자 보기 범위 | D-102 #15(관리자만 신고자를 봄), #16(탈퇴 신고자는 "탈퇴한 회원") | 관리자 신고 상세에만 신고자 닉네임 |
| 알림함·30초 확인·알림 설정 화면 | 003 FR-036~FR-054 | 005는 `NotificationWriter`로 쓰기만 한다 |
| 신고 처리 결과 알림(끌 수 있음) | 003 FR-051, `report_result` | `REPORT_RESOLVED` 그대로 |
| 관리자·블로그장 조치 알림(끌 수 없음) | 003 FR-050, FR-052 | `OWNER_WARNED`, `OWNER_REVOKED`, `POST_DELETED`. 이름은 005가 정한다. 003 plan이 다른 이름을 정하면 003 이름을 따른다 |
| 관리자 팔로우 거부 | 003 FR-006 | FR-004 확인 테스트에서 003 API가 있으면 함께 본다 |
| 알림 누르면 이동 | D-102 #21(운영 알림은 이동 없이 내용만) | 005 알림은 모두 이동 없이 내용만 보인다 |

- 003이 아직 없어도 005는 신고 행을 직접 넣어 테스트할 수 있다(004가 `follows`를 직접 넣은 것과 같다).
- 005가 더하는 알림 종류 5개(`OWNER_WARNED`, `OWNER_REVOKED`, `BLOG_HIDDEN`, `POST_HIDDEN`, `POST_RESTORED`)는 끌 수 없어 `notification_settings`는 그대로다.

## R-17 응답 시간

- 회원 검색: 이메일은 `uk_users_email` 일치. 닉네임 일부 일치는 `users` 전체를 읽지만 회원 10만 명까지 1초 안으로 본다.
- 블로그 검색: `LIKE` 세 칸을 OR로 묶어 `blogs`와 블로그장 조인을 읽는다.
- 신고함은 `idx_reports_route_status_created_at`, 활동 기록은 `idx_admin_actions_created_at`을 쓴다.
- `perf/AdminResponseTimeTest`가 회원 10,000명, 블로그 1,000개, 신고 5,000건으로 세 목록이 2초 안인지 확인한다(SC-001). 넘으면 닉네임 앞부분 일치로 바꾸는 것을 검토한다.
- 화면은 004의 `api.js` 5초 중단을 그대로 쓴다(D-48).

---

## 가정 모음 (문서·D-103에 없어 기본값으로 둔 것)

1. 회원 검색에서 관리자 계정은 뺀다. 탈퇴한 회원의 상세는 404다(R-04).
2. "전체 보기"는 관리자 한 명당 1분에 30번까지다(R-04).
3. 블로그 검색은 이름·주소·블로그장 닉네임 모두 일부 일치다. 폐쇄된 블로그는 30일 정리 전까지만 나온다. 글 수는 삭제되지 않은 글이다(R-05).
4. 블로그 숨김 해제 때는 알림을 보내지 않는다(R-07).
5. 블로그장 강퇴 사유는 선택(0~500자)이다. 새 블로그장에게는 따로 알림을 보내지 않는다(R-09).
6. 블로그가 없는 신고(메인 프로필 회원 신고)는 "문제 없음"으로만 처리한다. 신고함은 대기 중은 오래된 순, 처리됨은 최근 처리 순이다(R-10).
7. 관리자는 관리자 화면에서 공개 범위·숨김과 관계없이 글·댓글 내용을 본다(R-11).
8. 숨긴 글은 작성자가 링크로만 보고 목록에는 나오지 않는다. 작성자는 지울 수는 있지만 고칠 수 없다. 숨김·복구는 블로그 글만 한다(R-11).
9. 답글이 남은 최상위 댓글을 숨기면 "관리자가 숨긴 댓글입니다" 자리로 남는다. 숨긴 뒤 지운 댓글을 복구하면 보이는 상태로 돌아간다(R-11).
10. 폐쇄된 블로그의 글·댓글은 복구하지 않는다(R-11).
11. 일별 글 수에서 공지는 뺀다(R-12).
12. 관리자 페이지에 관리자가 아닌 회원이 오면 404, 비로그인이면 로그인 화면으로 보낸다(R-03).
13. 관리자 목록은 한 페이지 20개가 기본이고 10·20·50을 고를 수 있다(data-model 설정값).
14. 003의 신고 행 모양과 알림 이름은 003 명세를 기준으로 가정했다(R-16).

D-103 #8과 함께 부탁한 "D-94가 관리자 폐쇄도 블로그장이 철회할 수 있게 한 뜻이 맞는지" 확인은 2026-10-08 답이 왔다(D-104): 관리자 폐쇄는 블로그장이 철회할 수 없고 관리자만 철회한다.
