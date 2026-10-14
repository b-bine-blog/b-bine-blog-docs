---
description: "002 블로그 생성·참여·운영 구현 작업 목록"
---

# 작업 목록 (Tasks): 블로그 생성·참여·운영

**입력**: `specs/002-blog-management/`의 설계 문서

**선행 문서**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/blog-api.yaml](contracts/blog-api.yaml), [quickstart.md](quickstart.md)

**테스트**: 명세의 성공 기준(SC-001~SC-010)과 인수 시나리오가 경계값(7일, 04:00, 3개·5개)으로 정해져 있다. 그래서 001처럼 스토리마다 테스트 작업을 두고, 테스트를 먼저 쓴 뒤 구현한다.

**구성**: 사용자 스토리(US1~US9)별로 묶었다. 001의 부품(`IntegrationTestBase`, `FileStorage`, `ImageValidator`, `EmailMasker`, `DailyCleanupJob`)을 그대로 쓴다.

## 형식: `[ID] [P?] [Story] 설명`

- **[P]**: 동시에 해도 되는 작업(다른 파일, 끝나지 않은 작업에 의존하지 않음)
- **[Story]**: 이 작업이 속한 사용자 스토리(US1~US9)
- 경로 약속: 소스 `src/main/java/com/mainblog/`, 테스트 `src/test/java/com/mainblog/`, 화면 `src/main/resources/static/`
- 커밋 메시지에 작업 ID와 요구사항 ID를 적는다. 예: `T031 참여 신청 (BLG-04, D-98)`

---

## 1단계: 준비 (Setup)

- [X] T001 `src/main/resources/application.yml`에 data-model.md "설정값" 표의 `blog.*`, `blacklist.hash-secret` 키를 `${ENV:기본값}` 형식으로 더한다(비밀키는 기본값 없음). `src/test/resources/application-test.yml`에 테스트용 `blacklist.hash-secret`을 둔다 (D-68)
- [X] T002 [P] `.env.example`에 `BLACKLIST_HASH_SECRET`, `BLOG_LIMIT_PUBLIC`, `BLOG_LIMIT_PRIVATE`를 더하고 README 실행 방법의 환경변수 목록을 갱신한다
- [X] T003 [P] `src/main/java/com/mainblog/common/config/BlogProperties.java`, `BlacklistProperties.java`를 `@ConfigurationProperties`로 만든다. `blog.limit.public`이 1~5가 아니면 시작에 실패하게 한다(`@Validated`) (FR-011)

---

## 2단계: 기반 (Foundational)

**⚠️ 중요**: 이 단계를 끝내기 전에는 어떤 사용자 스토리도 시작하지 않는다.

- [X] T004 [P] 블로그 엔티티 `src/main/java/com/mainblog/blog/domain/Blog.java`(+`BlogRepository`, enum `Visibility`, `JoinPolicy`, `BlogStatus`, `CloseReason`)를 blogs 테이블에 맞춘다. `findByIdForUpdate`(PESSIMISTIC_WRITE)와 `findByAddress`를 둔다
- [X] T005 [P] `src/main/java/com/mainblog/blog/domain/BlogMember.java`(+Repository, enum `BlogRole`)를 만든다. `owner_blog_id`는 `insertable=false, updatable=false`로 읽기만 하고, `findByBlogIdAndUserId`, `findManagersOrderByManagerSince`를 둔다
- [X] T006 [P] 태그(`tags`, `blog_tags`)는 엔티티 없이 `BlogTagStore`(JdbcTemplate)로 읽고 쓴다. 이름으로 찾고 없으면 만든다 (구현 중 변경: 단순한 연결 테이블이라 JDBC로 둠)
- [X] T007 [P] `BlogJoinRequest`, `BlogDelegation`, `BlogSanction`, `BlogBlacklist`, `BlacklistAppeal`, `BlogShareLink` 엔티티와 Repository·enum을 (구독·폐쇄 알림 기록은 INSERT IGNORE를 쓰므로 JdbcTemplate) `src/main/java/com/mainblog/blog/domain/`에 만든다. 컬럼은 data-model의 규칙을 따른다
- [X] T008 [P] `src/main/java/com/mainblog/blog/domain/BlogCoverImage.java`를 만든다. images 테이블에 `@SQLRestriction("owner_type = 'BLOG_COVER'")`을 걸고, 001의 `ProfileImage`와 같은 방식으로 Repository를 둔다
- [X] T009 [P] reports(route=BLOG)는 처리만 하므로 엔티티 없이 `BlogReportService`(T063)에서 JdbcTemplate로 다룬다 (구현 중 변경)
- [X] T010 [P] `src/main/java/com/mainblog/common/tag/TagNormalizer.java`와 단위 테스트 `src/test/java/com/mainblog/common/tag/TagNormalizerTest.java`를 만든다. 테스트할 규칙은 6.4다: `#` 제거, trim, 가운데 공백은 `_`, 소문자, 1~20자 한글·영문·숫자·`_`, 중복 합치기 (research R-04)
- [X] T011 [P] `src/main/java/com/mainblog/common/masking/PhoneMasker.java`와 테스트를 만든다(`01012345678` → `010-****-5678`) (FR-046)
- [X] T012 [P] `src/main/java/com/mainblog/blog/application/BlacklistHasher.java`와 테스트를 만든다. 이름·이메일·전화번호를 정규화하고 HMAC-SHA256(`blacklist.hash-secret`)으로 16진수 64자를 만든다 (research R-09)
- [X] T013 [P] `src/main/java/com/mainblog/common/notification/NotificationWriter.java`, `NotificationType.java`, `NotificationSettingKey.java`와 테스트를 만든다 (research R-14)
  - `INSERT IGNORE`로 넣어 event_key 중복을 막는다.
  - 설정을 확인하되, 행이 없으면 모두 켜진 것으로 본다.
  - 알림 종류는 data-model의 "알림 종류" 표를 따른다.
- [X] T014 `src/main/java/com/mainblog/blog/application/BlogPermissionService.java`(빈 이름 `blogAuth`)를 만든다. `BlogPermission` enum은 VIEW·MEMBER·BLOG_INFO·MEMBER_MANAGE·POST_MANAGE·OWNER이고, `has(blogId, permission)`와 `require(...)`를 둔다 (research R-01, data-model 권한표)
  - 진행 중 정지면 `BLOG_SUSPENDED`(suspendedUntil, reason)로 거부한다.
  - CLOSED 블로그면 404로 거부한다.
  - SecurityConfig에서 메서드 보안(`@EnableMethodSecurity`)을 켠다.
- [X] T015 `src/main/java/com/mainblog/blog/application/BlogAccessPolicy.java`를 만든다. 열람 판단 규칙은 research R-06이다: PUBLIC은 누구나, LINK는 멤버·구독자·유효한 `BLOG_SHARE_{blogId}` 쿠키, PRIVATE은 멤버, CLOSED는 404
- [X] T016 `src/main/java/com/mainblog/common/error/ErrorCode.java`에 contracts의 오류 코드를 더한다: BLOG_NOT_FOUND, BLOG_FORBIDDEN, BLOG_SUSPENDED, ADMIN_NOT_ALLOWED, BLOG_ADDRESS_TAKEN, BLOG_LIMIT_EXCEEDED, ALREADY_MEMBER, ALREADY_OWNER, JOIN_PENDING_EXISTS, JOIN_REAPPLY_TOO_SOON, JOIN_NOT_PENDING, BLOG_BLACKLISTED, OWNER_CANNOT_LEAVE, NOT_SUSPENDED, ALREADY_SUSPENDED, REPORT_ALREADY_HANDLED, NOT_BLACKLISTED, APPEAL_PENDING_EXISTS, APPEAL_RETRY_TOO_SOON, APPEAL_NOT_PENDING, DELEGATION_PENDING_EXISTS, DELEGATION_NOT_PENDING, BLOG_CLOSING, BLOG_ALREADY_CLOSING, BLOG_NOT_CLOSING
  - 추가 필드(suspendedUntil, reason, appealAllowed, reapplyAt, retryAt)를 `ErrorResponse`에 넣는다.
  - `@PreAuthorize` 거부(AccessDeniedException)를 403 BLOG_FORBIDDEN으로 바꾼다.
- [X] T017 `src/main/java/com/mainblog/blog/api/BlogPageController.java`를 만든다. `/blog/{address}`와 그 아래 경로를 `blog/index.html`·`blog/manage.html`로 forward하고, SecurityConfig에서 `/blog/**`, `/blogs/**`를 permitAll로 둔다 (research R-03, FR-005)
- [X] T018 테스트 기반 `src/test/java/com/mainblog/support/IntegrationTestBase.java`의 `createOwnedBlog`를 새 엔티티 기준으로 바꾼다. 도우미 `addMember(blog, user, role)`, `subscribe`, `insertBlogReport`, `runDaily()`(DailyCleanupJob.runOnce), `notificationsOf(userId)`를 더한다

**체크포인트**: 기반 준비가 끝나면 스토리를 시작한다.

---

## 3단계: 사용자 스토리 1 — 블로그 만들기 (P1) 🎯 MVP

**목표**: 회원이 블로그를 만들고 블로그장이 된다. 주소 규칙·개수 제한·태그 규칙을 지킨다.

**독립 테스트**: quickstart 1~6

### 테스트

- [X] T019 [P] [US1] `src/test/java/com/mainblog/blog/BlogCreateIntegrationTest.java`를 만든다. US1 시나리오 1~7과 10~12를 다룬다: 생성·주소 형식·예약어·중복·이름 중복 허용·공개 3·비공개 5·비회원 401·관리자 403·태그
- [X] T020 [P] [US1] `src/test/java/com/mainblog/blog/BlogCreateConcurrencyTest.java`를 만든다. 공개 2개 가진 회원이 10번 동시 요청해도 공개가 3개를 넘지 않는지 확인하고(SC-002), 두 회원이 같은 주소를 동시에 요청하면 하나만 성공하는지 확인한다
- [X] T021 [P] [US1] `src/test/java/com/mainblog/blog/BlogLimitConfigTest.java`를 만든다. `@TestPropertySource(blog.limit.public=5)`로 4번째 공개 생성이 성공하는지 확인한다 (SC-003)

### 구현

- [X] T022 [P] [US1] `src/main/java/com/mainblog/blog/application/BlogAddressPolicy.java`를 만든다(형식·예약어) (FR-003, FR-004)
- [X] T023 [P] [US1] `src/main/java/com/mainblog/blog/application/BlogLimitPolicy.java`를 만든다 (FR-010, FR-013, research R-02)
  - `users` 행을 `SELECT ... FOR UPDATE`로 잠근다.
  - 지금 블로그장인 ACTIVE·CLOSING 블로그를 공개·비공개로 나눠 센다.
- [X] T024 [US1] `src/main/java/com/mainblog/blog/application/BlogService.create`를 만든다 (FR-001, FR-002, FR-006)
  - 관리자를 거부한다.
  - 이름 trim 후 1~30자, 소개 0~500자를 확인한다.
  - 태그를 정규화하고 최대 10개를 확인한다.
  - 개수 제한을 확인한다.
  - blogs, blog_members(OWNER, joined_at), tags·blog_tags를 저장한다.
  - visibility가 LINK면 공유 링크를 만든다.
  - 주소 유니크 위반은 BLOG_ADDRESS_TAKEN으로 바꾼다.
- [X] T025 [US1] `src/main/java/com/mainblog/blog/api/BlogController.java`에 `POST /api/blogs`와 `GET /api/blogs/address/{address}`를 만든다(BlogDetail: myRole·myPermissions 포함). contracts의 응답 형식을 따른다
- [X] T026 [US1] `src/main/java/com/mainblog/blog/application/BlogCoverImageService.java`와 `src/main/java/com/mainblog/blog/api/BlogCoverImageController.java`(`PUT`·`DELETE /api/blogs/{blogId}/cover-image`, BLOG_INFO 권한)를 만든다. 001의 ImageValidator·ImageSanitizer·FileStorage를 쓰고, 롤백되면 파일을 지운다 (FR-007, research R-05)
- [X] T027 [P] [US1] 블로그 만들기 화면 `src/main/resources/static/blogs/new.html`, `js/blog-new.js`를 만든다. 주소 형식은 화면에서도 미리 검사하고(최종 판단은 서버), 태그는 입력 칩으로 받는다. 생성한 뒤 대표 이미지를 올리고 `/blog/{주소}`로 이동한다
- [X] T028 [P] [US1] 블로그 홈 화면의 뼈대 `src/main/resources/static/blog/index.html`, `js/blog-home.js`를 만든다. 정보 표시는 textContent로 하고, 블로그장·부블로그장에게는 운영 메뉴 링크를 보여 준다

**체크포인트**: US1만으로 블로그를 만들고 들어갈 수 있다.

---

## 4단계: 사용자 스토리 2 — 블로그 찾고 참여하기 (P1)

**목표**: 목록·검색으로 찾아 참여를 신청하고, 승인·거절을 받고, 내 블로그 목록에서 본다.

**독립 테스트**: quickstart 7~9

### 테스트

- [X] T029 [P] [US2] `src/test/java/com/mainblog/blog/BlogListSearchIntegrationTest.java`를 만든다. US2 시나리오 1, 2, 12를 다룬다: 공개만 보이는지, 숨김을 빼는지, 인기순(멤버 수 → 최신), 10·20·30 이외 페이지 크기는 400, 검색어 2~20자 규칙, 태그 검색
- [X] T030 [P] [US2] `src/test/java/com/mainblog/blog/JoinRequestIntegrationTest.java`를 만든다. US2 시나리오 3~11과 13을 다룬다: 자유·승인제, 중복 대기, 7일 재신청(MutableClock 6일·8일), 취소 뒤 바로 재신청, 이미 멤버·블로그장, 차단 자동 거절, 블랙리스트 403, 관리자 403, 승인·거절 알림, 내 블로그 목록

### 구현

- [X] T031 [US2] `src/main/java/com/mainblog/blog/application/BlogQueryService.java`를 만든다 (FR-014, FR-015, research R-07)
  - 목록은 latest·popular 정렬로 만든다.
  - 검색은 FULLTEXT 구절 검색과 태그 일치 검색을 UNION으로 합친다.
  - 페이지 크기는 10·20·30만 받는다.
- [X] T032 [US2] `src/main/java/com/mainblog/blog/api/BlogController.java`에 `GET /api/blogs`, `GET /api/blogs/search`, `GET /api/me/blogs`를 더한다 (FR-014~FR-016)
- [X] T033 [US2] `src/main/java/com/mainblog/blog/application/JoinService.java`를 만든다 (FR-017~FR-024)
  - apply: research R-08의 확인 순서를 따른다. 신청자 행을 잠그고, member_count를 올리고, 알림을 보낸다.
  - approve·reject: 블로그 행을 잠그고 PENDING인지 다시 확인한다.
  - cancel: 신청자 본인만 할 수 있다.
- [X] T034 [US2] `src/main/java/com/mainblog/blog/api/JoinRequestController.java`를 만든다. 대상은 `POST`·`GET /api/blogs/{blogId}/join-requests`, `.../{requestId}/approval`, `.../rejection`, `DELETE /api/me/join-requests/{requestId}`이고, MEMBER_MANAGE는 `@PreAuthorize`로 확인한다
- [X] T035 [P] [US2] 메인 화면 `src/main/resources/static/index.html`, `js/blog-list.js`를 만든다. 최신·인기 탭과 번호 페이지를 두고, 10·20·30개 선택(기본 10)과 블로그 검색 칸을 둔다. 결과가 없으면 "검색 결과가 없습니다"를 보여 준다
- [X] T036 [P] [US2] 블로그 홈 화면 `js/blog-home.js`에 참여 신청·취소 버튼을 더한다. 대기 중이면 대기 표시를, 블랙리스트면 안내와 "문의하기"를 보여 준다
- [X] T037 [P] [US2] 내 블로그 화면 `src/main/resources/static/me/blogs.html`, `js/me-blogs.js`를 만든다. 운영하는 블로그와 참여한 블로그를 나눠 보여 주고, 부블로그장·폐쇄 예정을 표시한다. 상단 메뉴(`js/layout.js`)에 링크를 더한다

---

## 5단계: 사용자 스토리 3 — 블로그별 역할을 매 요청마다 확인 (P1)

**목표**: 다른 블로그 관리 요청은 모두 거부하고, 역할 변화는 다음 요청부터 반영한다.

**독립 테스트**: quickstart 10, 11

- [X] T038 [US3] `src/test/java/com/mainblog/blog/BlogRoleCheckIntegrationTest.java`를 만든다 (SC-004)
  - US3 시나리오 1~4를 다룬다.
  - contracts의 관리 API 전체를 표로 돌린다. A 블로그장·B 멤버 X가 B에 요청하면 모두 403이어야 한다.
  - 같은 쿠키로 정지·강퇴·위임·부블로그장 해제 직후 요청하면 거부돼야 한다.
  - 이 테스트는 US5~US8 API가 생기는 대로 표에 더한다.
- [X] T039 [US3] `src/test/java/com/mainblog/blog/BlogPermissionServiceTest.java`를 만든다. 역할 3개 × 권한 3개 × 6개 권한 이름의 조합이 data-model 권한표와 같은지 확인한다
- [X] T040 [US3] `BlogPermissionService.canDeletePost(blogId, authorId)`를 만든다. POST_MANAGE를 확인하고, 수정은 작성자만 할 수 있다(`canEditPost`). 글 API는 004에서 쓴다 (FR-037)

---

## 6단계: 사용자 스토리 4 — 공개 범위와 공유 링크 (P2)

**목표**: 공개·일부 공개·비공개에 따라 열람을 나누고, 공유 링크를 다시 만들 수 있게 하고, 공개 범위를 바꿀 때 알림을 보낸다.

**독립 테스트**: quickstart 12~14

### 테스트

- [X] T041 [P] [US4] `src/test/java/com/mainblog/blog/VisibilityIntegrationTest.java`를 만든다 (SC-007)
  - US4 시나리오 1~6을 다룬다.
  - 비공개로 바꿀 때 구독자 알림이 10건인지 확인한다.
  - 비공개 블로그를 공개로 바꿀 때도 개수 제한이 걸리는지 확인한다.
  - LINK를 벗어나면 링크가 막히고, LINK로 들어가면 새 링크가 생기는지 확인한다.

### 구현

- [X] T042 [US4] `src/main/java/com/mainblog/blog/application/ShareLinkService.java`를 만든다(만들기·다시 만들기·확인, 32바이트 base64url). `src/main/java/com/mainblog/blog/api/ShareLinkController.java`에 `GET`·`POST /api/blogs/{blogId}/share-link`와 `POST /api/blogs/share-access`(쿠키 굽기)를 만든다 (FR-026~FR-028)
- [X] T043 [US4] `src/main/java/com/mainblog/blog/application/SubscriptionService.java`와 `src/main/java/com/mainblog/blog/api/SubscriptionController.java`를 만든다. 대상은 `POST`·`DELETE /api/blogs/{blogId}/subscription`, `GET /api/me/subscriptions`다 (FR-029, research R-15)
- [X] T044 [US4] `BlogService.update`와 `PATCH /api/blogs/{blogId}`를 만든다 (FR-009, FR-013, FR-031, FR-032)
  - 요청은 JsonNode로 받고, 알 수 없는 필드나 address가 있으면 400이다.
  - name·description·tags는 BLOG_INFO, visibility·joinPolicy는 OWNER 권한이다.
  - visibility를 바꿀 때는 BlogLimitPolicy로 확인하고, 공유 링크를 전환하고, PRIVATE면 BLOG_PRIVATE 알림을 보낸다.
- [X] T045 [P] [US4] 블로그 홈 화면을 고친다. `?share=` 값을 `POST /api/blogs/share-access`로 보내고 replaceState로 주소에서 지운다. 일부 공개면 공유 버튼(링크 복사)을, 로그인한 회원에게만 구독하기 버튼을 보여 준다

---

## 7단계: 사용자 스토리 5 — 블로그 폐쇄와 철회 (P2)

**목표**: 폐쇄를 예약하고 철회할 수 있게 한다. 04:00 처리가 알림을 보내고, 폐쇄하고, 30일 뒤 정리한다.

**독립 테스트**: quickstart 21~25

### 테스트

- [X] T046 [P] [US5] `src/test/java/com/mainblog/blog/BlogClosingIntegrationTest.java`를 만든다 (SC-006)
  - US5 시나리오 1~6과 8~9를 다룬다.
  - MutableClock을 10/2 15:00, 10/6 04:00, 10/8 04:00, 10/9 04:00으로 옮기며 `runDaily()`를 부른다.
  - 받는 사람 1명당 알림이 정확히 3번(철회하면 철회 1번) 가는지 확인한다.
  - 같은 시각에 `runDaily()`를 두 번 불러도 중복이 0인지 확인한다.
  - 10/9 실행을 건너뛰어도 밀린 것까지 처리되는지 확인한다.
  - 23:59와 00:01 경계를 확인한다.
  - 폐쇄될 때 대기 중 신청·문의가 자동 거절되는지 확인한다.
- [X] T047 [P] [US5] `src/test/java/com/mainblog/blog/BlogPurgeIntegrationTest.java`를 만든다 (SC-009)
  - US5 시나리오 7을 다룬다.
  - 글·대댓글·댓글·좋아요·글 사진·대표 이미지·카테고리·블랙리스트·문의 행을 넣은 뒤 폐쇄하고 29일·31일 뒤를 확인한다.
  - 31일 뒤에는 내용이 0건, `address` NULL, blogs 행·blog_sanctions·reports가 남아 있어야 한다.
  - 같은 주소 재사용은 29일에 409, 31일에 성공해야 한다.

### 구현

- [X] T048 [US5] `src/main/java/com/mainblog/blog/application/BlogClosingService.java`를 만든다 (FR-072~FR-078, FR-084, research R-13)
  - `scheduleClose(blogId, reason)`: 블로그 행을 잠그고, 날짜 + 7일 04:00을 계산하고, 대기 중 위임을 취소하고, IMMEDIATE 알림을 보낸다.
  - `withdraw(blogId)`: OWNER만 할 수 있고, WITHDRAWN 알림을 보낸다.
  - `sendDueNotices(now)`: D3·D1을 보낸다.
  - `closeDue(now)`: 폐쇄하고 자동 거절·알림을 보낸다.
  - 알림 대상은 블로그장을 뺀 멤버와 구독자이고, 중복은 `blog_closing_notices` INSERT IGNORE로 막는다.
- [X] T049 [US5] `src/main/java/com/mainblog/blog/application/BlogPurgeService.java`를 만든다. 30일 정리의 지우는 순서는 research R-13이다: 대댓글 → 댓글 → 글 → 이미지 파일·행 → 카테고리 → 문의 → 블랙리스트 → 공유 링크 → 블로그 태그 → address NULL. 블로그마다 트랜잭션을 따로 쓴다 (FR-008, FR-060, FR-081)
- [X] T050 [US5] `src/main/java/com/mainblog/blog/application/BlogDailyTasks.java`를 만들고 `src/main/java/com/mainblog/batch/DailyCleanupJob.java`에서 부른다 (FR-074, FR-075)
  - 순서: 위임 만료 → D3·D1 알림 → 폐쇄 → 30일 정리 → 지운 대표 이미지 30일 정리
  - 단계마다 트랜잭션을 따로 쓰고 실패를 로그로 남긴다.
  - Result에 블로그 항목을 더한다.
- [X] T051 [US5] `src/main/java/com/mainblog/blog/api/ClosingController.java`에 `POST`·`DELETE /api/blogs/{blogId}/closing`(OWNER)을 만든다
- [X] T052 [US5] 001의 탈퇴 확인(`OwnedBlogQuery`)이 폐쇄 예정을 막고 폐쇄 뒤 허용하는지 `src/test/java/com/mainblog/member/WithdrawalIntegrationTest.java`에 실제 블로그로 한 경우를 더한다 (FR-080)

---

## 8단계: 사용자 스토리 6 — 블로그장 위임과 블로그 탈퇴 (P2)

**목표**: 위임 요청·수락·거절·자동 취소와 멤버의 블로그 탈퇴를 만든다.

**독립 테스트**: quickstart 19, 20

### 테스트

- [X] T053 [P] [US6] `src/test/java/com/mainblog/blog/DelegationIntegrationTest.java`를 만든다
  - US6 시나리오 1~5와 7을 다룬다.
  - 7일 만료는 04:00 처리로도, 응답 시점 확인으로도 되는지 본다.
  - 대기 중 요청이 있으면 두 번째 요청을 409로 막는지 본다.
  - 부블로그장이 위임받으면 권한이 사라지고 다른 부블로그장은 그대로인지 본다.
  - 이전 블로그장이 MEMBER로 남는지 본다.
- [X] T054 [P] [US6] `src/test/java/com/mainblog/blog/LeaveBlogIntegrationTest.java`를 만든다. US6 시나리오 6·7을 다룬다: 글 author_left, member_count, 받은 위임 요청 자동 취소

### 구현

- [X] T055 [US6] `src/main/java/com/mainblog/blog/application/DelegationService.java`를 만든다. request·accept·reject·cancelPending·expireDue를 두고, accept에서는 이전 블로그장을 먼저 바꾸고 flush한다. 알림 4종을 보낸다 (FR-066~FR-072, research R-12)
- [X] T056 [US6] `src/main/java/com/mainblog/blog/api/DelegationController.java`에 `POST`·`GET /api/blogs/{blogId}/delegation`, `.../acceptance`, `.../rejection`을 만든다
- [X] T057 [US6] `src/main/java/com/mainblog/blog/application/MemberManageService.leave`와 `DELETE /api/blogs/{blogId}/members/me`를 만든다. 블로그장이면 409를 주고, 멤버 행을 지우고, author_left를 표시하고, member_count를 줄이고, 받은 위임을 취소한다 (FR-064, FR-065)
- [X] T058 [US6] `src/main/java/com/mainblog/blog/application/OwnerSuccessionService.revokeOwner(blogId)`와 테스트를 만든다. 가장 먼저 부블로그장이 된 사람에게 넘기고, 없으면 OWNER_REVOKED로 폐쇄를 예약한다. 005가 부를 서비스다 (FR-082)

---

## 9단계: 사용자 스토리 7 — 멤버 제재와 블랙리스트 (P2)

**목표**: 경고·정지·해제·강퇴, 블로그 안 신고 처리, 블랙리스트 등록·열람을 만든다.

**독립 테스트**: quickstart 16, 17

### 테스트

- [X] T059 [P] [US7] `src/test/java/com/mainblog/blog/SanctionIntegrationTest.java`를 만든다
  - US7 시나리오 1~4와 6~8을 다룬다.
  - 정지 기간은 4가지만 받는다.
  - 정지 중 열람은 403 BLOG_SUSPENDED여야 하고, 다른 블로그는 열람할 수 있어야 한다.
  - 해제할 수 있고, 기간이 지나면 풀려야 한다.
  - 1년 안 3번이면 kickSuggested여야 한다. 1년이 지난 정지와 다른 블로그 정지는 빼야 한다.
  - 강퇴하면 블랙리스트에 해시로 오르고 원문이 없어야 한다.
  - 탈퇴 후 재가입한 사람과 같은 전화번호를 쓰는 다른 이메일 회원은 막혀야 한다.
  - 부블로그장 제재는 블로그장만 할 수 있어야 한다.
- [X] T060 [P] [US7] `src/test/java/com/mainblog/blog/BlogReportIntegrationTest.java`를 만든다. US7 시나리오 5를 다룬다: route=BLOG 신고만 목록에 나오고, 처리 4가지 결과와 신고자 알림, 이미 처리한 신고는 409

### 구현

- [X] T061 [US7] `src/main/java/com/mainblog/blog/application/SanctionService.java`를 만든다 (FR-048~FR-051, FR-053~FR-056, research R-10)
  - 대상 확인: 블로그장은 대상이 될 수 없고, 부블로그장은 블로그장만 제재할 수 있다.
  - 경고·정지·해제를 처리한다.
  - 강퇴는 멤버 행 삭제, author_left, member_count, 블랙리스트 등록, 받은 위임 취소를 한 트랜잭션에서 한다.
  - 정지 횟수를 계산한다.
  - 끌 수 없는 알림을 보낸다.
- [X] T062 [US7] `src/main/java/com/mainblog/blog/api/SanctionController.java`에 `POST`·`GET /api/blogs/{blogId}/members/{userId}/sanctions`를 만든다
- [X] T063 [US7] `src/main/java/com/mainblog/blog/application/BlogReportService.java`와 `src/main/java/com/mainblog/blog/api/BlogReportController.java`를 만든다. 대상은 `GET /api/blogs/{blogId}/reports`와 `POST .../{reportId}/resolution`이다 (FR-052, research R-11)
  - 대상 회원은 target_type으로 찾는다.
  - SanctionService를 부르고 report_id를 연결한다.
  - 신고자에게 알림을 보낸다.
- [X] T064 [US7] `src/main/java/com/mainblog/blog/application/BlacklistService.java`를 만든다: `isBlacklisted(blogId, user)`, `list`. `GET /api/blogs/{blogId}/blacklist`를 만든다. 응답에는 등록일·강퇴 사유·강퇴한 사람 닉네임·해제 여부만 넣는다 (FR-057~FR-059)
- [X] T065 [P] [US7] 운영 화면 `src/main/resources/static/blog/manage.html`, `js/blog-manage.js`를 만든다. 탭은 참여 신청, 멤버(제재 버튼, 정지 기간 4가지 선택), 신고, 블랙리스트이고, 권한에 따라 탭을 보이거나 숨긴다. 서버가 최종 판단한다

---

## 10단계: 사용자 스토리 8 — 부블로그장 지정과 멤버 정보 보기 (P2)

**목표**: 부블로그장 지정·해제·권한 체크박스를 만들고, 가린 멤버 정보를 보여 준다.

**독립 테스트**: quickstart 14, 15

### 테스트

- [X] T066 [P] [US8] `src/test/java/com/mainblog/blog/ManagerIntegrationTest.java`를 만든다 (SC-005)
  - US8 시나리오 1~6을 다룬다.
  - 체크박스마다 허용·거부를 확인한다.
  - 부블로그장이 지정·위임·폐쇄·공개 범위를 요청하면 항상 403이어야 한다.
  - 마스킹 예시 2개를 확인하고, 응답 본문 전체에 원문 이메일·전화번호가 0건인지 확인한다.
  - 해제한 직후 요청부터 막혀야 한다.

### 구현

- [X] T067 [US8] `MemberManageService`에 setManager·removeManager·listMembers를 더한다. listMembers는 가린 이메일·전화번호와 정지 상태·횟수를 넣는다. `src/main/java/com/mainblog/blog/api/MemberManageController.java`에 `GET /api/blogs/{blogId}/members`, `PUT`·`DELETE /api/blogs/{blogId}/managers/{userId}`를 만든다 (FR-039~FR-047)
- [X] T068 [P] [US8] 운영 화면 멤버 탭에 부블로그장 지정·해제와 권한 체크박스 3개를 더한다(블로그장에게만 보임). 정보 수정 탭(이름·소개·대표 이미지·태그, 블로그장에게는 공개 범위·참여 방식도)과 위임·폐쇄 탭을 더한다. 위임할 멤버가 없거나 폐쇄 예정이면 위임 버튼을 숨긴다 (FR-070, FR-071)

---

## 11단계: 사용자 스토리 9 — 블랙리스트 해제 문의 (P3)

**목표**: 블랙리스트에 걸린 사람이 문의를 남기고, 관리자가 일치 여부를 보고 해제하거나 거절한다.

**독립 테스트**: quickstart 18

- [X] T069 [P] [US9] `src/test/java/com/mainblog/blog/BlacklistAppealIntegrationTest.java`를 만든다
  - US9 시나리오 1~3을 다룬다.
  - 대기 중 문의는 하나만 둘 수 있어야 한다.
  - 거절 뒤 7일 안에는 409, 7일 뒤에는 다시 문의할 수 있어야 한다.
  - 블랙리스트가 아닌 사람은 409 NOT_BLACKLISTED여야 한다.
  - 응답에 해시·원문이 없어야 한다.
  - 해제 뒤 참여 신청이 성공해야 한다.
- [X] T070 [US9] `src/main/java/com/mainblog/blog/application/AppealService.java`를 만든다 (FR-061~FR-063)
  - create: 맞는 블랙리스트를 고르고, name_matched·phone_matched를 계산하고, 대기·7일 규칙을 확인한다.
  - release·reject: 블로그 행을 잠그고 알림을 보낸다.
  - `blacklist-appeals` API 4개를 `BlacklistController`에 더한다.
- [X] T071 [P] [US9] 블로그 홈의 블랙리스트 안내에 문의하기 입력 창을 만든다. 운영 화면에 해제 문의 탭을 만들어 일치 여부 표시, 해제·거절 버튼을 둔다

---

## 12단계: 마무리 (Polish)

- [X] T072 [P] `src/test/java/com/mainblog/contract/OpenApiConformanceTest.java`가 `contracts/blog-api.yaml`도 읽어, 경로·메서드가 모두 컨트롤러에 있는지 확인하게 한다
- [X] T073 [P] `src/test/java/com/mainblog/perf/BlogResponseTimeTest.java`를 만든다. 블로그 1,000개를 넣고 목록·검색이 2초 안에 응답하는지 확인한다 (SC-001)
- [X] T074 [P] 화면 반응형을 점검한다. 모바일 폭(360px)에서 가로 스크롤이 없고, 블로그 데이터는 모두 textContent로 넣었는지(innerHTML 0건) 확인한다 (SC-010, D-64)
- [X] T075 보안 점검: 관리 API 전체에 `@PreAuthorize`가 붙었는지 확인하는 테스트를 만든다. 오류 응답과 로그에 이메일·전화번호·해시가 남지 않는지도 확인한다 (헌장 I·II·III)
- [X] T076 quickstart.md의 시나리오를 실제로 돌리고 "확인 결과" 절을 적는다. 전체 테스트를 통과시킨다

---

## 의존 관계와 순서

- 1단계 → 2단계 → 스토리 순서로 진행한다.
- US1(생성)은 모든 스토리의 전제다.
- US2(참여)는 US3·US6·US7·US8에서 멤버를 만드는 데 쓴다. 테스트에서는 `addMember` 도우미로 대신할 수 있다.
- US3 테스트(T038)는 US4~US8 API가 생길 때마다 표에 더한다.
- US5(폐쇄)는 US6의 위임 취소(T055 `cancelPending`)를 부른다. 그래서 T048은 T055를 만든 뒤에 하거나, 빈 메서드를 먼저 둔다.
- US7의 강퇴(T061)는 블랙리스트 해시(T012)를 쓴다. US2의 블랙리스트 확인(T033)은 T064의 `isBlacklisted`를 쓴다. 그래서 T064의 조회 부분을 T033 전에 만든다.
- US9는 US7 다음에 한다.

## 동시에 할 수 있는 예

- 2단계: T004~T013은 서로 다른 파일이라 함께 해도 된다.
- US1: T019·T020·T021(테스트), T022·T023(정책), T027·T028(화면)
- US5~US8: 테스트 작성(T046, T047, T053, T054, T059, T060, T066)을 먼저 함께 하고 구현은 차례로 한다.

## 구현 전략

1. **MVP**: 1·2단계와 US1을 한다. 블로그를 만들고 들어갈 수 있다.
2. **P1 완성**: US2·US3을 한다. 찾기, 참여, 역할 확인이 된다. 여기까지가 "함께 운영하는 블로그"의 최소 단위다.
3. **P2**: US4 → US5 → US6 → US7 → US8 순서로 한다. 폐쇄·위임이 회원탈퇴 조건과 이어진다.
4. **P3와 마무리**: US9를 하고 12단계를 한다.
