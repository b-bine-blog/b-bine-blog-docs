---
description: "005 메인 관리자·제재 구현 작업 목록"
---

# 작업 목록 (Tasks): 메인 관리자와 제재

**입력**: `specs/005-admin-moderation/`의 설계 문서

**선행 문서**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/admin-api.yaml](contracts/admin-api.yaml), [quickstart.md](quickstart.md)

**테스트**: 성공 기준(SC-001~SC-010)이 경계값으로 정해져 있다. 경고 3번째, 1년, 30일, 알림 정확히 3번, 동시 10번, 원문 노출 0건이다. 그래서 스토리마다 테스트 작업을 두고 테스트를 먼저 쓴다.

**구성**: 사용자 스토리(US1~US7)별로 묶었다. 001·002·004의 부품을 그대로 쓴다.
- 테스트: `IntegrationTestBase`, `BlogTestBase`, `BoardTestBase`, `MutableClock`
- 블로그: `BlogClosingService`, `OwnerSuccessionService`, `BlogAccessPolicy`, `SuspensionQuery`
- 공통: `EmailMasker`, `PhoneMasker`, `NotificationWriter`, `RateLimiter`, `DailyCleanupJob`

**DB 변경**: `comments.deleted_by`, `owner_warnings.reason` 두 칸은 사용자 승인 뒤 T057에서 넣는다. T001~T056은 승인 전에 할 수 있다(plan "구현 전에 할 일").

## 형식: `[ID] [P?] [Story] 설명`

- **[P]**: 동시에 해도 되는 작업(다른 파일, 끝나지 않은 작업에 의존하지 않음)
- **[Story]**: 이 작업이 속한 사용자 스토리(US1~US7)
- 경로 약속: 소스 `src/main/java/com/mainblog/`, 테스트 `src/test/java/com/mainblog/`, 화면 `src/main/resources/static/`
- 커밋 메시지에 작업 ID와 요구사항 ID를 적는다. 예: `T030 블로그장 경고 (ADM-07, D-103 #12)`

---

## 1단계: 준비 (Setup)

- [X] T001 `application.yml`에 data-model "설정값"의 `admin.*`를 `${ENV:기본값}`으로 더한다 (D-68)
- [X] T002 [P] `common/config/AdminProperties.java`를 `@ConfigurationProperties("admin")`로 만든다
- [X] T003 [P] `common/error/ErrorCode`에 `OWNER_CHANGED`, `ALREADY_HIDDEN`, `NOT_HIDDEN`, `NOT_RESTORABLE`, `BLOG_ALREADY_CLOSED`(모두 409)를 더한다 (research R-14)
- [X] T004 [P] `common/notification/NotificationType`에 `OWNER_WARNED`, `OWNER_REVOKED`, `BLOG_HIDDEN`, `POST_HIDDEN`, `POST_RESTORED`(모두 OPERATION, 끌 수 없음)를 더한다 (data-model 알림 종류)
- [X] T005 [P] `admin/application/ActionType.java`(research R-06의 16가지)와 `TargetType.java`를 만든다

---

## 2단계: 기반 (Foundational)

**⚠️ 중요**: 이 단계를 끝내기 전에는 어떤 사용자 스토리도 시작하지 않는다.

- [X] T006 `auth/security/JwtAuthenticationFilter`가 DB에서 읽은 role이 ADMIN이면 `ADMIN` 권한을 붙인다. `common/config/SecurityConfig`에 다음을 더한다 (FR-001~FR-003, SEC-11, research R-02)
  - `/api/admin/**` `hasAuthority("ADMIN")`
  - `AccessDeniedHandler`: 403 `ADMIN_ONLY` JSON. CSRF 거부는 지금처럼 403
- [X] T007 [P] `admin/application/AdminGuard.java`(DB role 확인, `ADMIN_ONLY`)와 `AdminGuardTest`를 만든다
- [X] T008 [P] `admin/application/AdminActionLog.java`(조치와 같은 트랜잭션에서 `admin_actions` 쓰기, memo 500자 자르기)와 `AdminPaging.java`(10·20·50, 기본 20)를 만든다 (FR-039, research R-06)
- [X] T009 화면 틀을 만든다 (D-103 #1, research R-03)
  - `admin/api/AdminPageController.java`: `GET /admin`, `/admin/**`에서 role 확인 뒤 `src/main/resources/admin/index.html`. 비로그인은 로그인 화면, 관리자가 아니면 404
  - `admin/index.html`: 탭 6개 틀
  - `static/js/admin-common.js`: 세션 확인, 탭, 표/카드 그리기를 모두 textContent로
  - `css/base.css`: 관리자 표·탭, 좁은 화면은 카드
- [X] T010 [P] `static/js/layout.js`: 세션 `admin`이 true면 "관리자" 링크를 보이고 "블로그 만들기·내 블로그"를 숨긴다 (D-90)
- [X] T011 `src/test/java/com/mainblog/admin/AdminTestBase.java`를 `BoardTestBase` 확장으로 만든다. 관리자 로그인, 관리자 신고 행 직접 넣기(003 없이), 경고 행 넣기, 활동 기록 읽기 도우미를 둔다 (research R-16)
- [X] T012 [P] `admin/AdminAccessIntegrationTest`: 아래를 확인한다 (SC-002, FR-002)
  - `/admin`: 비로그인 → 로그인 화면, 회원·블로그장 404, 관리자 200
  - `/api/admin/stats`: 비회원 401, 회원 403 `ADMIN_ONLY`(본문에 회원 정보 없음)
  - 관리자 role을 USER로 바꾸면 다음 요청부터 403

**체크포인트**: 관리자만 들어오는 틀 완료.

---

## 3단계: 사용자 스토리 1 - 관리자 전용 접근과 회원 조회 (P1) 🎯 MVP

**독립 테스트**: 관리자로 회원을 찾고 상세·"전체 보기"를 확인하고, 다른 계정으로 같은 요청이 거부되는지 본다.

- [X] T013 [P] [US1] `admin/AdminMemberIntegrationTest` (US1-1~5, SC-003, D-103 #2~#5)
  - 검색: 닉네임 일부, 이메일 전체(대소문자 무시), 이메일 일부는 0건, 탈퇴 회원·관리자 계정 제외, size 10·20·50·30(400)
  - 상세: `abcdef@gmail.com` → `ab***@gmail.com`, `ab@x.com` → `a***@x.com`, `010-****-5678`, 이름 보임, 응답에 원문·비밀번호 칸 없음, 비공개 블로그 포함 운영·참여 블로그와 역할, 블로그별 경고 이력. 탈퇴 회원은 404
  - "전체 보기": 원문, `PRIVACY_VIEW` 1건(관리자·시각·대상), `Cache-Control: no-store`, 31번째 429 `RATE_LIMITED`, CSRF 없으면 403
- [X] T014 [P] [US1] `admin/AdminBlogActivityDeniedTest`: 관리자의 블로그 만들기·참여 신청·글쓰기·댓글·좋아요가 403 `ADMIN_NOT_ALLOWED`, 공지 쓰기는 성공. 003 팔로우 API가 있으면 팔로우도 403 (US1-8, FR-004, SC-008)
- [X] T015 [US1] `admin/application/AdminMemberService.java`를 만든다. 검색(LIKE 이스케이프), 상세(`EmailMasker`·`PhoneMasker`), 전체 보기(`RateLimiter` + `AdminActionLog` 같은 트랜잭션) (FR-005~FR-009)
- [X] T016 [US1] `admin/api/AdminMemberController.java`를 만든다. `GET /api/admin/members`, `GET /api/admin/members/{userId}`, `POST /api/admin/members/{userId}/privacy-view` (contracts)
- [X] T017 [US1] 화면 `static/js/admin-members.js`: 회원 탭을 만든다. 검색 종류 선택, 목록, 상세 패널, "전체 보기" 버튼은 그 상세에서만 원문 표시. 상세를 다시 열면 API를 새로 불러 다시 가린다 (D-103 #5)

**체크포인트**: 관리자 회원 조회 동작.

---

## 4단계: 사용자 스토리 2 - 블로그 조회·숨김·강제 폐쇄 (P1)

- [X] T018 [P] [US2] `admin/AdminBlogQueryIntegrationTest` (US2-1, D-103 #6)
  - 이름·주소·블로그장 닉네임으로 찾는다. 공개·일부 공개·비공개 모두 나온다
  - 상태: 운영 중·폐쇄 예정·폐쇄됨(30일 정리 전만)·숨김, status로 거르기
  - 멤버 4·글 12: 삭제 글은 빼고 숨긴 글은 센다
  - 상세: 부블로그장 목록, 대기 중 위임 요청, 지금 블로그장 경고 수
- [X] T019 [P] [US2] `admin/AdminBlogHideIntegrationTest` (US2-2, FR-012, D-103 #7)
  - 숨기면 메인 목록·블로그 검색·피드·통합 검색·태그에서 빠진다
  - 비회원·다른 회원·구독자·공유 링크 쿠키·관리자 일반 화면은 404. 블로그장·멤버는 보고 글을 쓴다
  - 블로그장만 `BLOG_HIDDEN` 1건, 멤버는 0건. `BLOG_HIDE` 기록. 다시 숨기면 409 `ALREADY_HIDDEN`
  - 해제하면 다시 보이고 `BLOG_UNHIDE` 기록, 알림 없음. 숨김이 아닌데 해제하면 409 `NOT_HIDDEN`
  - 폐쇄된 블로그는 409 `BLOG_ALREADY_CLOSED`
- [X] T020 [P] [US2] `admin/AdminForceCloseIntegrationTest` (US2-3~6, FR-013, FR-014, D-94, D-103 #8, D-104)
  - 10월 2일 15:00(MutableClock)에 폐쇄하면 10월 9일 04:00으로 예약된다
  - 블로그장을 뺀 멤버·구독자에게 즉시·10/6 04:00·10/8 04:00에 한 번씩 알림, 중복 0
  - 10월 9일 04:00에 폐쇄되고 글이 안 보인다(30일 정리는 002 테스트로 갈음)
  - ~~블로그장 철회는 성공 + 철회 알림, 관리자가 철회 API를 부르면 403~~ → D-104: 블로그장 철회는 403 `ADMIN_CLOSE_LOCKED`, 관리자 철회(`DELETE /api/admin/blogs/{id}/force-close`)는 204 + 철회 알림 + `RESTORE` 기록. 블로그장 폐쇄를 관리자가 철회하면 409 `NOT_ADMIN_CLOSE`, 관리자가 아니면 403, CSRF 없으면 403
  - 이미 폐쇄 예정이면 시각 그대로, 알림 다시 없음, `close_reason = ADMIN`, `keptExisting: true`
  - 폐쇄된 블로그는 409. `BLOG_FORCE_CLOSE` 기록
- [X] T021 [US2] `blog/application/BlogAccessPolicy.canView`: 숨김이고 멤버가 아니면 false로 바꾼다. 002 `VisibilityIntegrationTest`에 숨김 사례를 더한다 (FR-012, D-103 #7)
- [X] T022 [US2] `blog/application/BlogClosingService.markAdminClose(blogId)`를 더한다. 폐쇄 예정이면 `close_reason`만 ADMIN으로 바꾸고 시각·알림은 그대로 둔다 (D-103 #8)
- [X] T023 [US2] `admin/application/AdminBlogService.java`를 만든다. 검색·상세(JdbcTemplate), 숨김·해제(+ `BLOG_HIDDEN` 알림), 강제 폐쇄(`closeBySystem(ADMIN)` 또는 `markAdminClose`), 기록 (FR-011~FR-013)
- [X] T024 [US2] `admin/api/AdminBlogController.java`를 만든다. `GET /api/admin/blogs`, `GET /api/admin/blogs/{blogId}`, `PUT·DELETE /api/admin/blogs/{blogId}/hidden`, `POST /api/admin/blogs/{blogId}/force-close` (contracts)
- [X] T025 [US2] 화면 `static/js/admin-blogs.js`: 블로그 탭을 만든다. 검색·상태 거르기, 목록, 상세, 숨김·해제·강제 폐쇄 버튼과 확인 창("7일 뒤 04:00에 폐쇄됩니다")

**체크포인트**: 관리자가 블로그를 찾고 숨기고 폐쇄할 수 있다(사용자가 말한 "블로그를 관리할 수 없음" 해결).

---

## 5단계: 사용자 스토리 3 - 블로그장 경고와 강퇴(권한 박탈) (P2)

- [X] T026 [P] [US3] `admin/OwnerWarningIntegrationTest` (US3-1·2·10·11, FR-020, FR-021, D-95, D-103 #12·#13)
  - 사유: 빈 값·501자는 400
  - 첫 경고: `OWNER_WARNED`에 사유와 "3번 중 1번"이 들어가고 신고자는 없다. `OWNER_WARNING` 기록
  - 세 번째 경고에 박탈된다
  - 1년 지난 경고는 세지 않는다. 블로그 A·C는 따로 센다
  - 새 블로그장은 0부터, 전 블로그장이 다시 블로그장이 되면 자기 경고를 다시 센다
  - `ownerId`가 지금 블로그장이 아니면 409 `OWNER_CHANGED`. 폐쇄된 블로그는 409
- [X] T027 [P] [US3] `admin/OwnerRevocationIntegrationTest` (US3-3~9, FR-022~FR-029, D-17, D-54, D-103 #14~#17)
  - 바로 강퇴: 경고 0이어도 박탈. S1(10/1)·S2(10/3) 중 S1이 수락 없이 블로그장, 전 블로그장은 MEMBER, `OWNER_REVOKED` 알림
  - S1이 공개 블로그 3개를 운영해도 넘어간다(D-103 #16)
  - 부블로그장 없음: 10/2 15:00 강퇴 → 10/9 04:00 예약. 문구 "블로그장 권한 박탈로 인한 폐쇄 조치". 박탈된 P를 뺀 멤버·구독자에게 3번씩, 중복 0. 폐쇄 전까지 글쓰기·댓글이 되고 아무도 철회할 수 없다
  - 블로그장이 폐쇄를 누른 블로그
    - 부블로그장 있음: 위임되고 폐쇄 예정 유지, 새 블로그장은 철회할 수 있다
    - 부블로그장 없음: 시각 유지, 알림 다시 없음
  - 대기 중 위임 요청은 `AUTO_CANCELED`, 받는 멤버에게 `DELEGATION_CANCELED` 1건
  - 새 블로그장이 전 블로그장을 002 제재로 정지할 수 있다
  - 관리자용 멤버 경고·정지·강제 퇴장 API가 없다(FR-010)
  - 기록: `OWNER_KICK` + `AUTO_DELEGATE` 또는 `CLOSE_SCHEDULE`
- [X] T028 [P] [US3] `admin/OwnerConcurrencyTest`: 경고 2번인 블로그장에게 관리자 둘이 동시에 경고 10번을 보낸다. 박탈 1건(`owner_revocations` 1행), 위임 또는 폐쇄 예약 1번, 나머지는 409 `OWNER_CHANGED` (SC-005, FR-028)
- [X] T029 [US3] `admin/application/OwnerRevocationService.java`를 만든다. 블로그 행 잠금 안에서 아래를 한 번에 한다 (research R-09, data-model 박탈 순서)
  - 위임 요청 자동 취소 + 알림
  - `OwnerSuccessionService.revokeOwner`
  - `owner_revocations`, `OWNER_REVOKED` 알림, 기록
  - `BlogClosingService`: `closeBySystem`에 뺄 회원(박탈된 사람)을 넘긴다. 3일 전·1일 전 대상 쿼리에서 `owner_revocations`(이 블로그·이 폐쇄 예정 시각)의 user_id를 뺀다 (US3-5)
- [X] T030 [US3] `admin/application/OwnerWarningService.java`를 만든다. 잠금 → `ownerId` 확인 → 사유 검사 → `owner_warnings` → 1년 안 경고 수 → 알림 → 3번이면 `OwnerRevocationService.revoke(WARNING_3)` (FR-020, FR-021)
- [X] T031 [US3] `admin/api/AdminOwnerController.java`를 만든다. `GET·POST /api/admin/blogs/{blogId}/owner-warnings`, `POST /api/admin/blogs/{blogId}/owner-revocation` (contracts)
- [X] T032 [US3] 블로그 상세 화면(`admin-blogs.js`)에 경고(사유 입력, "지금 n번") 버튼과 바로 강퇴 버튼, 확인 창, 경고 이력을 붙인다

---

## 6단계: 사용자 스토리 4 - 블로그·블로그장 신고 처리 (P2)

- [X] T033 [P] [US4] `admin/AdminReportIntegrationTest` (US4-1~8, FR-030~FR-034, D-93, D-102 #15·#16, D-103 #18)
  - 신고함
    - `route = 'ADMIN'` 4종(블로그·블로그장·블로그장 글·메인 프로필)만 나온다. 멤버 글 신고(BLOG)는 없고, 블로그장 신고함에는 ADMIN 신고가 없다
    - 대기 중은 오래된 순, 처리됨은 최근 순
  - 상세: `target_snapshot`, 신고자 닉네임, 탈퇴 신고자는 "탈퇴한 회원"
  - 처리 결과
    - NONE: 조치 없음
    - OWNER_WARNING: 사유 필수, 경고 수 +1, 3번째에 박탈
    - OWNER_KICK: 박탈
    - BLOG_CLOSE: 폐쇄(이미 폐쇄 예정이면 사유만)
  - 처리 대상
    - 블로그장이 바뀌었으면 409 `OWNER_CHANGED`
    - `blog_id` NULL 신고는 NONE만(나머지 400)
  - 한 번만: 다시 처리하면 409 `REPORT_ALREADY_HANDLED`, 동시 두 처리는 하나만 성공
  - 알림: `REPORT_RESOLVED`. 신고자가 `report_result`를 껐으면 0건(처리·기록은 남음)
  - 신고 5건이 쌓여도 자동 조치 없음
  - 기록: `REPORT_HANDLE`, 조치 행과 `owner_warnings.report_id`
- [X] T034 [US4] `admin/application/AdminReportService.java`를 만든다. 목록·상세, 처리(블로그 행 → 신고 행 잠금, R-08·R-09 서비스 호출, 알림, 기록) (research R-10)
- [X] T035 [US4] `admin/api/AdminReportController.java`를 만든다. `GET /api/admin/reports`, `GET /api/admin/reports/{reportId}`, `POST /api/admin/reports/{reportId}/resolution` (contracts)
- [X] T036 [US4] 화면 `static/js/admin-reports.js`: 신고 탭을 만든다. 대기·처리 탭, 상세(당시 내용 textContent), 결과 선택·사유 입력·확인 창

---

## 7단계: 사용자 스토리 5 - 게시글·댓글 숨김·삭제와 복구 (P2)

- [X] T037 [P] [US5] `admin/AdminPostModerationIntegrationTest` (US5-1~4, FR-015~FR-019, D-103 #9~#11)
  - 숨김
    - 목록·검색·피드에서 빠진다
    - 작성자 상세는 `hiddenByAdmin: true`이고 수정·댓글·좋아요는 막힌다. 블로그장·비회원은 404
    - `POST_HIDDEN` 1건, 30일 정리 뒤에도 남는다
    - 해제하면 다시 보이고 알림은 없다
  - 삭제: `POST_DELETED`, 사진 안 보임. 004 경로(`DELETE /api/posts/{id}`)로 지워도 `POST_DELETE` 기록
  - 관리자 수정은 403
  - 복구
    - 10/1 삭제 → 10/20 복구: 보이고 사진도 보임, `POST_RESTORED`
    - 숨긴 채 지운 글은 HIDDEN으로 돌아간다
    - 작성자가 지운 글은 409 `NOT_RESTORABLE`
    - 10/31 04:00 정리 뒤에는 404
    - 폐쇄 블로그 글은 409
    - 복구 뒤 다시 지우면 알림이 다시 간다
  - 관리자 글 목록·상세: 비공개·숨김 블로그 글도 보이고 `deletedBy`·`restorable`이 있다
- [X] T038 [P] [US5] `admin/AdminCommentModerationIntegrationTest` (US5-5, D-103 #9·#11)
  - 댓글 숨김·해제·삭제는 작성자 알림 0건, 활동 기록이 남는다
  - 답글이 남은 최상위 댓글을 숨기면 `hidden: true` 자리가 남고 답글은 보인다
  - 관리자가 지운 댓글 복구는 성공, 작성자가 지운 댓글은 409, 30일 뒤는 404
- [X] T039 [US5] `admin/application/AdminPostModerationService.java`를 만든다. 목록·상세·숨김·해제·삭제·복구, 알림, 기록 (research R-11)
- [X] T040 [US5] `admin/application/AdminCommentModerationService.java`를 만든다. 목록·숨김·해제·삭제·복구, 기록. 누가 지웠는지는 칸 추가 전에는 `admin_actions`의 `COMMENT_DELETE`로 판단한다
- [X] T041 [US5] 004 글 쪽을 고친다 (D-103 #10)
  - `board/application/PostQueryService`·`PostPolicy`: HIDDEN 글은 작성자에게만 `hiddenByAdmin`으로 보이고, 수정·댓글·좋아요·공유는 막는다
  - `PostService.delete`: 관리자면 `AdminPostModerationService`로 보낸다. `POST_DELETED` 키에 삭제 시각을 넣는다
  - `specs/004-board/contracts/board-api.yaml`의 `PostDetail`에 `hiddenByAdmin`을 더한다
  - 004 테스트에서 깨지는 것을 맞춘다
- [X] T042 [US5] 004 댓글 쪽을 고친다
  - `board/application/CommentService`: HIDDEN 댓글은 빼고, 답글이 남은 HIDDEN 최상위 댓글은 `hidden: true` 자리로 둔다
  - `board-api.yaml` 댓글 스키마에 `hidden`을 더한다
- [X] T043 [US5] `admin/api/AdminContentController.java`를 만든다. `GET /api/admin/posts`, `GET·DELETE /api/admin/posts/{postId}`, `PUT·DELETE /api/admin/posts/{postId}/hidden`, `POST /api/admin/posts/{postId}/restore`, `GET /api/admin/comments`, `DELETE /api/admin/comments/{commentId}`, `PUT·DELETE /api/admin/comments/{commentId}/hidden`, `POST /api/admin/comments/{commentId}/restore` (contracts)
- [X] T044 [US5] 화면을 만든다
  - `static/js/admin-content.js`: 글·댓글 탭. 블로그·상태 거르기, 본문은 글자로만, 숨김·삭제·복구 버튼
  - `static/js/board-post.js`: "관리자가 숨긴 글" 표시와 "관리자가 숨긴 댓글입니다" 자리

---

## 8단계: 사용자 스토리 6 - 관리자 활동 기록과 운영 기록 1년 보관 (P2)

- [X] T045 [P] [US6] `admin/AdminActionLogIntegrationTest` (US6-1, FR-039, SC-004, D-103 #20)
  - 16가지 조치마다 관리자·시각·종류·대상이 맞는 행 1개
  - 목록: 종류·관리자·대상·기간으로 거르기, 관리자 닉네임, 탈퇴 대상은 "탈퇴한 회원", 지워진 대상은 "삭제된 대상"
  - 고치기·지우기 경로가 없다
  - 조치가 실패해 되돌려지면 기록도 없다
- [X] T046 [P] [US6] `admin/AdminDailyTasksIntegrationTest` (US6-2~4, FR-038, D-103 #19)
  - 31일 뒤 04:00: 활동·경고·박탈·신고·멤버 정지 기록이 그대로다
  - 366일 뒤: 모두 지워진다
  - 남는 것: 효력 있는 영구 정지, 블랙리스트가 가리키는 강제 퇴장
  - 지운 신고를 가리키던 남은 행의 `report_id`는 NULL
  - 탈퇴 30일 뒤 개인정보가 지워진 회원의 기록도 남는다("탈퇴한 회원")
- [X] T047 [US6] `admin/application/AdminActionQueryService.java`와 `admin/api/AdminActionController.java`(`GET /api/admin/actions`)를 만든다
- [X] T048 [US6] `admin/application/AdminDailyTasks.java`(research R-13 순서, 단계마다 트랜잭션)를 만들고 `batch/DailyCleanupJob`에 단계와 로그를 더한다 (SCL-03)
- [X] T049 [US6] 화면 `static/js/admin-actions.js`: 활동 기록 탭을 만든다. 거르기와 목록

---

## 9단계: 사용자 스토리 7 - 운영 통계 (P3)

- [X] T050 [P] [US7] `admin/AdminStatsIntegrationTest` (US7-1~3, FR-040, D-103 #21)
  - 10/1 회원 3명, 10/2 회원 5명과 관리자 1명 가입
  - 회원 수 8 → 1명 탈퇴하면 7이고 10/2 가입 수는 그대로 5
  - 블로그 4(숨김 포함, 폐쇄 제외)
  - 10/2 글 7(그중 삭제·숨김도 셈, 공지 제외)
  - 30일 0 채우기, `admin.stats.daily-days` 바꾸면 개수가 바뀐다
  - 회원이 부르면 403
- [X] T051 [US7] `admin/application/AdminStatsService.java`와 `admin/api/AdminStatsController.java`(`GET /api/admin/stats`)를 만든다
- [X] T052 [US7] 화면 `static/js/admin-stats.js`: 통계 탭을 만든다. 숫자 카드 2개, 일별 표

---

## 10단계: 다듬기 (Polish)

- [X] T053 [P] `contract/OpenApiConformanceTest`에 `ADMIN_CONTRACT = specs/005-admin-moderation/contracts/admin-api.yaml`의 경로·메서드 대조를 더하고, "계약에 없는 API 없음" 검사에도 넣는다(T041·T042로 바뀐 board-api.yaml 포함)
- [X] T054 [P] `admin/AdminSecurityTest` (SC-002, SC-003, FR-003, FR-007, FR-009)
  - 계약의 모든 `/api/admin/**` 경로·메서드를 아래 계정으로 부른다
    - 비회원: 401
    - 회원·블로그 멤버·블로그장·부블로그장: 403 `ADMIN_ONLY`, 본문에 회원 정보 없음
    - 권한 회수된 관리자: 403
  - 상태를 바꾸는 요청에 CSRF가 없으면 403
  - "전체 보기" 응답을 뺀 관리자 응답 전체와 로그에 이메일·전화번호 원문, 비밀번호 칸이 0건
  - "전체 보기"마다 `PRIVACY_VIEW` 1건
  - `admin/index.html`은 static에서 직접 받을 수 없다
- [X] T055 [P] `perf/AdminResponseTimeTest`: 회원 10,000명, 블로그 1,000개, 신고 5,000건으로 회원 검색·블로그 검색·신고함이 2초 안이다 (SC-001)
- [ ] T056 [P] 관리자 화면 6개 탭을 360px·1280px에서 확인한다. 가로 스크롤이 없고 `api.js` 5초 중단 안내가 나와야 한다 (SC-010, D-48)
- [X] T057 **(DB 변경 승인 뒤)** Crowfoot 문서 654에 `comments.deleted_by`, `owner_warnings.reason`을 더한다. `admin_actions.action_type` 설명도 고친다(research R-15). `plan_migration` → 사용자 승인 → `apply_migration` → `export_ddl`로 `docs/04-design/schema.sql`을 갱신한다. 그다음 아래를 고치고 T038·T026에 사례를 더한다
  - 004 `CommentService.delete`가 `deleted_by`를 채운다
  - 댓글 복구 판단을 `deleted_by <> author_id`로 바꾼다
  - 경고가 `reason`을 저장하고 경고 이력에 보인다
- [X] T058 003 plan·구현과 맞춘다. 신고 행 모양(`reports` 칸, 사유 값)과 알림 이름(`OWNER_WARNED` 등)이 다르면 data-model·계약·`NotificationType`을 고친다. 003 신고 버튼으로 만든 신고가 관리자 신고함에 들어오는지 본다 (research R-16)
- [X] T059 `local/seed.sql`에 관리자 신고 예시(블로그·블로그장·블로그장 글), 숨긴 글, 블로그장 경고 1건을 더하고 `SeedSqlTest`를 맞춘다
- [X] T060 quickstart.md "확인 결과"를 채우고 README의 기능 목록을 갱신한다

---

## 의존 관계와 실행 순서

- 1단계 → 2단계 → US1(MVP) → US2.
- US3은 US2 뒤다(블로그 상세 화면, 강제 폐쇄 서비스).
- US4는 US2·US3 뒤다(처리 결과가 폐쇄·경고·강퇴를 부름).
- US5는 2단계 뒤에 US2~US4와 따로 해도 된다.
- US6의 T045는 다른 스토리의 조치가 다 있어야 하므로 US2~US5 뒤에 한다. T046·T048은 2단계 뒤 언제든 된다.
- US7은 2단계 뒤 언제든 된다.
- 10단계는 모든 스토리 뒤. T057은 사용자 승인이 난 뒤에만 한다.
- 같은 파일을 고치는 작업은 차례로 한다: `admin-blogs.js`(T025·T032), `BlogClosingService`(T022·T029), `board-api.yaml`(T041·T042), `DailyCleanupJob`(T048).

---

## 구현하며 바뀐 점

구현 중에 계획과 달라진 것을 적는다. "사용자 확인 필요"로 표시한 것은 문서·D-103으로 정해지지 않아 가장 덜 바꾸는 쪽을 고른 것이다.

1. **T057 스키마 반영을 1단계로 당겼다.** `comments.deleted_by`, `owner_warnings.reason`, `admin_actions.action_type` 설명은 개발 DB(Crowfoot 문서 654)에 이미 반영되어 있어 `docs/04-design/schema.sql`을 손으로 맞추고 시작했다. 그래서 경고는 처음부터 `reason`에 저장하고(T030), 댓글 복구는 처음부터 `deleted_by`로 판단한다(T040). `admin_actions`의 `COMMENT_DELETE`로 판단하는 임시 방식은 만들지 않았다.
2. **T011** `AdminTestBase`는 `BoardTestBase` 대신 003의 `SocialTestBase`(BoardTestBase를 확장)를 확장했다. 탈퇴 처리·알림 도우미를 같이 쓰려고.
3. **T053 일부를 2단계에서 했다.** 관리자 API가 생기면 바로 `OpenApiConformanceTest`의 "계약에 없는 API 없음"이 깨지므로 `ADMIN_CONTRACT`를 그 검사에 먼저 넣었다. 계약의 모든 경로가 매핑됐는지 보는 검사는 10단계에서 더했다.
4. **T009** 관리자 화면을 열 때 액세스 토큰(15분)만 만료되고 로그인 유지 토큰(RT)이 있으면 로그인 화면으로 보내지 않고 `js/admin-refresh.js`가 토큰을 한 번 새로 받아 다시 연다. 다른 화면은 `api.js`가 같은 일을 하지만 `/admin`은 서버가 먼저 role을 봐서 따로 두었다. 실패하면 `/login.html?next=/admin`으로 간다.
5. **T006** CSRF 거부는 지금처럼 본문 없는 403이고, 로그인했지만 관리자가 아닌 `/api/admin/**` 요청만 403 `ADMIN_ONLY` JSON이다.
6. **T029** 002 `DelegationIntegrationTest`의 "박탈된 사람도 멤버로서 폐쇄 알림을 받는다" 확인을 "받지 않는다"로 바꿨다. 005 FR-024·US3-5("박탈된 사람을 제외한 멤버 전원과 구독자")가 002 구현보다 뒤의 결정이라서다. `OwnerSuccessionService.revokeOwner`가 박탈된 사람을 즉시 알림에서 빼고, 3일 전·1일 전 알림은 `owner_revocations`(이 블로그·이 폐쇄 예정 시각)로 뺀다.
7. **T029 (사용자 확인 필요)** 박탈 때 받는 멤버에게 가는 `DELEGATION_CANCELED` 알림은 002에 이미 있는 종류를 그대로 써서 탭이 "블로그"다. data-model 알림 표는 "운영" 탭으로 적었지만, 종류의 탭을 바꾸면 002의 위임 취소 알림(블로그장에게 가는 것)까지 바뀌어 그대로 두었다. 끌 수 없는 것은 같다.
8. **T032** 경고 확인 창의 "기준 횟수"는 블로그 상세 응답에 없어(계약 `BlogDetail`) "기준 횟수(기본 3번)"로 적었다. 실제 판단과 "3번 중 n번" 알림 문구는 서버 설정값(`admin.warning.revoke-threshold`)을 쓴다.
9. **T034** 신고 처리에서 "처리 대상이 지금 블로그장인지" 확인은 경고·강퇴뿐 아니라 블로그 폐쇄에도 한다(계약 설명대로). 문제 없음은 확인하지 않는다. 신고 사유는 003처럼 코드(SPAM 등)로 주고, 화면이 `/api/reports/reasons`로 이름을 붙인다.
10. **T041** 숨긴 글은 `PostPolicy.requireReadableForDetail`로 글 상세(`GET /api/posts/{id}`)에서만 작성자 본인에게 보인다(`hiddenByAdmin: true`, `canEdit`·`canComment`·`shareable`은 false, 조회수는 세지 않음). 댓글 목록·댓글 쓰기·좋아요·수정은 004의 `requireReadable`을 그대로 써서 404다(403이 아님). 작성자는 숨긴 글을 지울 수 있고, 블로그장·글 관리 권한자는 숨긴 글을 볼 수도 지울 수도 없다(404).
11. **T041** 004 `PostService`가 관리자 패키지를 직접 알지 않도록 `PostService.AdminPostDelete` 인터페이스를 두고 `AdminPostModerationService`가 구현한다(`@Lazy`로 순환 의존을 끊음). 작성자 알림 문구는 `PostService.notifyDeleted` 하나로 같이 쓴다.
12. **T042** 숨긴 최상위 댓글 자리는 `hidden: true`, `deleted: false`, 내용·작성자 null이다. 화면(`board-post.js`)은 "관리자가 숨긴 댓글입니다"로 보인다. 004 `CommentService.delete`는 이제 `deleted_by`를 채운다.
13. **T040 (사용자 확인 필요)** `deleted_by` 칸이 생기기 전에 지워진 댓글(`deleted_by` NULL)은 누가 지웠는지 알 수 없어 복구 대상에서 뺐다(`restorable: false`, 복구하면 409 `NOT_RESTORABLE`). 개발 DB에 그런 행이 있으면 30일 안에만 문제가 된다.
14. **T048** 멤버 제재 기록(`blog_sanctions`)의 1년 기준은 `created_at` 대신 제재한 시각 `starts_at`으로 했다. 002가 `created_at`을 DB 기본값(DB 시계)으로 채워 서버 시계(`Clock`)와 어긋날 수 있어서다. 실제 운영에서는 두 값이 같다. 활동 기록·경고·박탈·신고는 서비스가 `created_at`을 서버 시계로 채우므로 그대로 `created_at`을 쓴다.
15. **T045** "조치가 실패하면 기록도 없다"는 같은 트랜잭션에서 조치와 기록을 쓰고 일부러 실패시켜 둘 다 없는 것을 확인했다. `AdminActionLog.write`는 트랜잭션 밖에서 부르면 실패한다(`MANDATORY`).
16. **T051** 일별 가입·글 수는 시작일 00:00부터 내일 00:00 전까지만 센다. `users.created_at`은 DB 기본값이라 서버 시계와 어긋난 행이 오늘 뒤 날짜로 잡히지 않게 위쪽 경계도 두었다. T050의 "설정값을 바꾸면 개수가 바뀐다"는 Spring 문맥을 새로 띄우지 않고 설정값만 바꾼 서비스를 만들어 확인했다.
17. **T053** 관리자 계약은 경로 22개(메서드 27개, D-104 뒤 28개)가 모두 매핑됐는지와 모든 경로가 `/api/admin/`인지 본다. 004 `board-api.yaml`에 `PostDetail.hiddenByAdmin`, 댓글 `hidden`을 더했다(경로·메서드는 그대로).
18. **T055** `perf/AdminResponseTimeTest`에 통계(`/api/admin/stats`)도 넣었다.
19. **T056 (사용자 확인 필요, 하지 않음)** 이 작업 환경에서는 앱을 띄울 수 없어(bootRun 금지) 360px·1280px 화면 확인을 하지 못했다. quickstart 26번대로 `local/start.sh`로 띄워 직접 봐야 한다.
20. **T057** Crowfoot 문서 반영(`plan_migration`·`apply_migration`)은 사용자가 이미 개발 DB에 해 두었고, `docs/04-design/schema.sql`은 손으로 맞췄다(1번). 코드 쪽(`deleted_by` 채우기, 경고 `reason` 저장·이력 표시)은 T030·T040·T042에서 처음부터 했다.
21. **T058** 003과 맞춰 볼 것: 신고 사유는 003의 코드 값(`SPAM` 등), 결과 이름(`OWNER_WARNING`·`OWNER_KICK`·`BLOG_CLOSE`)과 `ReportResultNotifier`의 문구가 이미 맞았다. 003 신고 버튼(`POST /api/reports`)으로 만든 블로그·블로그장·블로그장 글·메인 프로필 신고가 관리자 신고함에 들어오고 멤버 글 신고는 블로그장 신고함에만 가는 것을 `AdminReportIntegrationTest`에서 확인했다. 알림 이름(`OWNER_WARNED`·`OWNER_REVOKED`·`BLOG_HIDDEN`·`POST_HIDDEN`·`POST_RESTORED`)은 2단계에서 더한 그대로다.
22. **D-103 #8 (해결 → D-104)** D-103 #8에서 부탁한 "관리자 폐쇄도 블로그장이 철회할 수 있다(D-94)"는 뜻 확인에 2026-10-08 사용자가 "관리자가 강제 폐쇄한 블로그는 블로그장이 취소할 수 없게 막고, 관리자 폐쇄는 관리자만 되돌린다"고 정했다(D-104). `BlogClosingService.withdraw`는 `close_reason = ADMIN`이면 403 `ADMIN_CLOSE_LOCKED`. 관리자 철회 `DELETE /api/admin/blogs/{blogId}/force-close`(204)를 더했다: 관리자 폐쇄인 폐쇄 예정만(아니면 409 `BLOG_NOT_CLOSING`, 다른 사유면 409 `NOT_ADMIN_CLOSE`), 블로그장 철회와 같은 철회 알림, 기록은 새 action_type을 늘리지 않으려고(스키마 설명 변경 없이) 기존 `RESTORE`·`BLOG`에 memo "강제 폐쇄 철회". 관리자 블로그 상세에 "폐쇄 철회" 버튼, 블로그장 관리 화면은 관리자 폐쇄면 철회 버튼을 숨기고 안내 문구를 보인다. 002 계약·명세(FR-084)도 맞췄다. 계약 메서드는 28개(`AdminSecurityTest`).
