---
description: "004 게시판 구현 작업 목록"
---

# 작업 목록 (Tasks): 게시판(글·댓글·검색·피드·공유)

**입력**: `specs/004-board/`의 설계 문서

**선행 문서**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/board-api.yaml](contracts/board-api.yaml), [quickstart.md](quickstart.md)

**테스트**: 성공 기준(SC-001~SC-013)이 경계값(30자, 5,000자, 3MB, 10장, 10개, 하루 1번, 30일)으로 정해져 있다. 그래서 스토리마다 테스트 작업을 두고 테스트를 먼저 쓴다.

**구성**: 사용자 스토리(US1~US10)별로 묶었다. 001·002의 부품(`IntegrationTestBase`, `BlogTestBase`, `BlogPermissionService`, `BlogAccessPolicy`, `ImageValidator`, `ImageSanitizer`, `FileStorage`, `TagNormalizer`, `NotificationWriter`, `RateLimiter`, `DailyCleanupJob`)을 그대로 쓴다.

## 형식: `[ID] [P?] [Story] 설명`

- **[P]**: 동시에 해도 되는 작업(다른 파일, 끝나지 않은 작업에 의존하지 않음)
- **[Story]**: 이 작업이 속한 사용자 스토리(US1~US10)
- 경로 약속: 소스 `src/main/java/com/mainblog/`, 테스트 `src/test/java/com/mainblog/`, 화면 `src/main/resources/static/`
- 커밋 메시지에 작업 ID와 요구사항 ID를 적는다. 예: `T020 글 쓰기 (BRD-01, D-92)`

---

## 1단계: 준비 (Setup)

- [X] T001 `build.gradle`에 `org.commonmark:commonmark:0.24.0`, `commonmark-ext-gfm-tables:0.24.0`, `commonmark-ext-gfm-strikethrough:0.24.0`, `org.jsoup:jsoup:1.18.1`을 더한다 (research R-01)
- [X] T002 `application.yml`에 data-model "설정값"의 `board.*`, `app.base-url`을 `${ENV:기본값}`으로 더하고 `spring.servlet.multipart.max-request-size`를 11MB로 올린다 (D-68)
- [X] T003 [P] `common/config/BoardProperties.java`, `AppProperties.java`를 `@ConfigurationProperties`로 만든다
- [X] T004 [P] `static/vendor/toastui/`에 Toast UI Editor 3.2.2 배포 파일(js·css)과 LICENSE를 넣는다. `static/img/og-default.png`(1200×630)를 만든다 (R-02, D-100 #15)
- [X] T005 [P] `.env.example`, `local/start.sh`, `local/start.bat`에 `APP_BASE_URL`을 더한다

---

## 2단계: 기반 (Foundational)

**⚠️ 중요**: 이 단계를 끝내기 전에는 어떤 사용자 스토리도 시작하지 않는다.

- [X] T006 [P] `common/markdown/MarkdownRenderer.java`(commonmark → jsoup Safelist)와 `MarkdownRendererTest`(XSS 사례 모음: script, onerror, javascript: 링크, data: 이미지, iframe, style, 표·코드·취소선 유지)를 만든다 (FR-005, SC-002, R-01)
- [X] T007 [P] `common/markdown/MarkdownText.java`(글자만 뽑은 요약 n자, 첫 이미지 주소, `/files/` 이미지 이름 목록)와 테스트를 만든다 (D-100 #7·#14, R-03)
- [X] T008 [P] `board/domain/Post.java`(+Repository, enum `BoardType`, `PostStatus`), `Category.java`, `Comment.java`(+`CommentStatus`), `PostImage.java`(images, `@SQLRestriction("owner_type = 'POST'")`) 의 열과 상태값을 스키마에 맞춘다. 게시판 테이블은 엔티티 없이 모두 JdbcTemplate로 다룬다(구현 때 단순화, 002 `members` 조회와 같은 방식)
- [X] T009 [P] `common/notification/NotificationType`에 `POST_COMMENT`(COMMENT, post_comment), `COMMENT_REPLY`(COMMENT, comment_reply), `POST_LIKE`(LIKE, post_like), `POST_DELETED`(OPERATION, 없음), `NOTICE`(OPERATION, notice)를 더한다 (data-model 알림 종류)
- [X] T010 [P] `common/error/ErrorCode`에 `POST_NOT_FOUND`, `POST_FORBIDDEN`, `POST_IMAGE_LIMIT`, `CATEGORY_NOT_FOUND`, `CATEGORY_DUPLICATE`, `CATEGORY_LIMIT_EXCEEDED`, `COMMENT_NOT_FOUND`, `COMMENT_FORBIDDEN`, `COMMENT_NOT_ALLOWED`, `LIKE_NOT_ALLOWED`, `SEARCH_KEYWORD_INVALID`, `ADMIN_ONLY`를 더한다. 크기 초과는 001·002와 같이 400 `FILE_TOO_LARGE`로 둔다(계약도 400으로 맞춤)
- [X] T011 `board/application/PostVisibility.java`(공개 피드·검색용 SQL 조건, 차단 조건, 구독 탭 조건)와 `AuthorView.java`(ACTIVE·LEFT_BLOG·WITHDRAWN 표시)를 만든다 (R-04, R-05)
- [X] T012 `board/application/PostPolicy.java`(쓰기·수정·삭제·댓글·좋아요 가능 여부, 블로그 열람·정지 확인을 002 서비스로)와 단위 테스트를 만든다 (FR-002, FR-008~FR-010, D-90, D-100 #1)
- [X] T013 `src/test/java/com/mainblog/board/BoardTestBase.java`에 글·카테고리·댓글·차단·구독 데이터 만들기 도우미를 둔다(002 `BlogTestBase` 확장)

**체크포인트**: 기반 준비 완료.

---

## 3단계: 사용자 스토리 1 - 글 쓰기·읽기·수정·삭제 (P1) 🎯 MVP

**독립 테스트**: 멤버가 글을 쓰고, 비회원이 읽고, 작성자·블로그장·다른 멤버·관리자가 수정·삭제를 시도한다.

- [X] T014 [P] [US1] `board/PostWriteIntegrationTest`: 제목 1·30·31자, 본문 5,000·5,001자(공백·기호 포함), 비회원·비멤버·관리자 쓰기 403, 폐쇄 예정 블로그 쓰기 성공, 정지 회원 403 (US1-1~4·14·15)
- [X] T015 [P] [US1] `board/PostReadIntegrationTest`: 상세 contentHtml 걸러짐, 제목 `<b>`는 그대로 문자열, 비공개·일부 공개·삭제 글 404, 작성자 표시 "탈퇴한 계정"·"탈퇴한 회원" (US1-5·6·12, FR-016)
- [X] T016 [P] [US1] `board/PostEditDeleteIntegrationTest`: 작성자 수정 성공, 블로그장·관리자 수정 403, 다른 멤버 삭제 403, 블로그장·POST_MANAGE 부블로그장·관리자 삭제 성공 + POST_DELETED 알림, 다른 블로그 블로그장 403, 블로그를 떠난 작성자 수정·삭제 403 (US1-7~10, SC-004, D-100 #1)
- [X] T017 [US1] `board/application/PostService.java`(쓰기·수정·삭제, 태그·이미지 연결 호출)와 `PostQueryService.java`(상세 응답, canEdit·canDelete·canComment·shareable)를 만든다
- [X] T018 [US1] `board/application/PostTagService.java`(TagNormalizer, 최대 10개, 전체 교체)를 만든다 (FR-023~FR-028)
- [X] T019 [US1] `board/api/PostController.java`: `POST /api/blogs/{blogId}/posts`, `GET·PUT·DELETE /api/posts/{postId}` (contracts)
- [X] T020 [US1] `board/api/PostPageController.java`: `/blog/{주소}/write`, `/blog/{주소}/posts/{id}/edit` → write.html forward, `/blog/{주소}/posts/{id}` → post.html(우선 og 없이)
- [X] T021 [US1] 화면 `static/blog/write.html` + `js/board-write.js`: Toast UI 마크다운 에디터, 제목·카테고리·태그 입력, 글자 수 표시, localStorage 자동 저장·복원, 5분 로그인 연장과 만료 5분 전 확인 창 (FR-004, FR-014, D-62)
- [X] T022 [US1] 화면 `static/blog/post.html` + `js/board-post.js`: 본문만 innerHTML, 나머지 textContent, 수정·삭제 버튼("글을 정말 삭제하시겠습니까" 확인), 상단 메뉴 공통 (FR-006, FR-012, FR-072)

**체크포인트**: 글 쓰고 읽기 동작.

---

## 4단계: 사용자 스토리 2 - 글 목록·페이징·카테고리 (P1)

- [X] T023 [P] [US2] `board/PostListIntegrationTest`: 글 35개 size 10·20·30 페이지 수, 50은 400, 3페이지 바로 가기, 최신순, thumbnailUrl = 첫 이미지, 카테고리 필터·미분류(0), 삭제 글 제외 (US2-1~6)
- [X] T024 [P] [US2] `board/CategoryIntegrationTest`: POST_MANAGE만 추가·수정·삭제·순서, 일반 멤버 403, 30개 초과 409, 이름 31자 400, 중복 409, 삭제하면 글이 미분류 (US2-7, D-100 #8)
- [X] T025 [US2] `PostQueryService.list`(번호 페이지, 카테고리 필터, 댓글 수·첫 이미지)와 `GET /api/blogs/{blogId}/posts`를 만든다
- [X] T026 [US2] `board/application/CategoryService.java`와 `board/api/CategoryController.java`(목록·추가·이름 변경·삭제·순서)를 만든다
- [X] T027 [US2] 블로그 홈 `static/blog/index.html` + `js/blog-home.js`에 글 목록(번호 페이지, 개수 선택), 카테고리 목록, 글쓰기 버튼(멤버만), PC 마우스 올리면 첫 사진, 모바일은 오른쪽 작은 첫 사진을 붙인다 (FR-019, D-100 #7)
- [X] T028 [US2] 운영 화면 `static/blog/manage.html` + `js/blog-manage.js`에 카테고리 관리 탭을 붙인다

---

## 5단계: 사용자 스토리 3 - 메인 피드 (P1)

- [X] T029 [P] [US3] `board/FeedIntegrationTest`: 비회원 최신 탭에 공개 블로그 글만, 인기 P(8)·R(3, 나중)·Q(3) 순서, 구독 탭 20개 + nextCursor, 30일 넘은 글 제외, 비공개로 바뀐 블로그는 멤버 아닌 구독자에게 안 보임, 삭제·차단 직후 다음 조회에 빠짐, 팔로우 탭(follows 행 직접 넣음), 비회원 구독·팔로우 탭 401 (US3, SC-008, D-100 #18)
- [X] T030 [US3] `board/application/FeedService.java`와 `board/api/FeedController.java`(`GET /api/feed`)를 만든다
- [X] T031 [US3] 메인 `static/index.html` + `js/board-feed.js`에 피드 탭(최신·인기·구독·팔로우), 번호 페이지와 "더 보기"를 붙인다

---

## 6단계: 사용자 스토리 4 - 이미지 첨부 (P2)

- [X] T032 [P] [US4] `board/PostImageIntegrationTest`: 2.9MB 다섯 형식 성공, 3MB 초과 400, svg·pdf·zip·확장자만 바꾼 exe 400, 한 요청 11장 400, 10MB 초과 400, GPS EXIF가 저장 파일에 없음, `../../etc/passwd.jpg`가 UUID 이름, 비멤버 403, 글 저장 때 11번째 이미지 400, 남이 올린 이미지 이름은 연결 안 됨, 수정 때 빠진 이미지 owner_id NULL (US4, SC-003)
- [X] T033 [US4] `board/application/PostImageService.java`(업로드, 연결, 해제)와 `board/api/PostImageController.java`(`POST /api/blogs/{blogId}/images`)를 만든다
- [X] T034 [US4] 글쓰기 화면에 Toast UI `addImageBlobHook` 업로드를 붙인다

---

## 7단계: 사용자 스토리 5 - 댓글·대댓글·좋아요 (P2)

- [X] T035 [P] [US5] `board/CommentIntegrationTest`: 1~500자, 비회원·관리자 403, 공지 400, 답글 @닉네임(닉네임 바꾸면 바뀜), 답글의 답글은 같은 단계 + 대상 바뀜, 수정됨 표시, 남의 수정·삭제 403, 블로그장·POST_MANAGE 삭제 성공, 답글 있는 삭제 → "삭제된 댓글입니다" → 답글 모두 삭제 → 사라짐, 탈퇴 회원 "탈퇴한 회원", 공유 링크로 보는 회원 일부 공개 글에 댓글 성공, 차단한 회원 댓글 숨김·같은 블로그 멤버면 보임, POST_COMMENT·COMMENT_REPLY 알림과 설정 끔·자기 댓글 알림 없음 (US5, D-100 #1~3·#9~11·#13)
- [X] T036 [P] [US5] `board/LikeIntegrationTest`: 누르기·취소 토글, 동시 10번 → 1개(SC-006), 취소 후 다시 눌러도 알림 1건, 자기 글 알림 없음, 1분 31번째 429, 관리자 403, 공지 400 (US5-8·9, D-100 #12·#13)
- [X] T037 [US5] `board/application/CommentService.java`, `CommentQueryService.java`와 `board/api/CommentController.java`를 만든다
- [X] T038 [US5] `board/application/LikeService.java`와 `board/api/LikeController.java`(`PUT /api/posts/{postId}/like`)를 만든다
- [X] T039 [US5] 글 상세 화면에 좋아요 버튼과 댓글 목록·입력·답글·수정·삭제(textContent)를 붙인다

---

## 8단계: 사용자 스토리 6·7 - 통합 검색·최근 검색어·태그 (P2)

- [X] T040 [P] [US6] `board/SearchIntegrationTest`: ALL에 블로그+글, TAG·NICKNAME 정확히 일치, 검색어 1·21자·공백·특수문자만 400, 결과 없음 빈 목록, 관련도·최신·인기(좋아요 같으면 최신) 정렬, 35개 페이지, 비공개·일부 공개·숨김·삭제·차단 글과 블로그 제외(개수 포함), 탈퇴 회원 닉네임 제외 (US6-1~7, SC-007, D-100 #16)
- [X] T041 [P] [US6] `board/RecentSearchIntegrationTest`: 11개 검색하면 10개, 같은 말 다시 검색하면 맨 앞(중복 없음), 하나 삭제·전체 삭제, 남의 것 안 보임·삭제 404, 비회원 저장 안 함 (US6-8·9, D-100 #17)
- [X] T042 [P] [US7] `board/TagPostIntegrationTest`: `#맛집`·` 서울 `·`Java`·`제주 여행`·`java` 중복 정리, 11개·21자·`c++` 400, 태그 목록에서 비공개·일부 공개·삭제 글 제외 (US7, SC-009)
- [X] T043 [US6] `board/application/SearchService.java`, `RecentSearchService.java`와 `SearchController`, `RecentSearchController`를 만든다
- [X] T044 [US7] `board/api/TagPostController.java`(`GET /api/tags/{name}/posts`)를 만든다
- [X] T045 [US6] 화면 `static/search.html` + `js/board-search.js`(분류바·정렬·페이지·"검색 결과가 없습니다"·최근 검색어), `static/tags/index.html` + `js/board-tag.js`, 메인 검색창을 통합 검색으로 연결한다. `/search`, `/tags/{이름}` forward를 둔다

---

## 9단계: 사용자 스토리 8 - 조회수 (P3)

- [X] T046 [P] [US8] `board/ViewCountIntegrationTest`: 처음 1, 같은 날 20번 그대로, 다음 날(MutableClock) +1, 23:59·00:01 두 번, 비회원 VID 쿠키 생성·재사용, 회원 쿠키 없이 다시 열어도 그대로, 작성자 본인 안 셈, UA `Googlebot`·`crawler` 안 셈, 같은 IP 61번째 글 안 셈, 동시 두 요청 1번 (US8, SC-005, D-100 #20·#21)
- [X] T047 [US8] `board/application/ViewCountService.java`를 만들고 글 상세 조회에 붙인다

---

## 10단계: 사용자 스토리 9 - 글 링크 공유와 미리보기 (P3)

- [X] T048 [P] [US9] `board/OgTagIntegrationTest`: 공개 글 og:url·og:title("제목 - 닉네임")·og:description(마크다운 기호 뺀 100자)·og:image(첫 이미지 절대 주소), 이미지 없으면 블로그 대표 이미지, 그것도 없으면 사이트 기본, 일부 공개 글은 share 값이 맞을 때만, 비공개·삭제 글은 기본 미리보기, `"><script>` 제목 이스케이프, shareable 값 (US9, SC-010, D-100 #5·#6·#14·#15)
- [X] T049 [US9] `board/application/OgTagRenderer.java`를 만들고 `PostPageController`가 post.html의 `<!--OG-->` 자리를 채우게 한다
- [X] T050 [US9] 글 상세 화면에 링크 복사 버튼을 붙인다(PUBLIC 글 주소, LINK 글 주소 + share, PRIVATE 숨김, 주소의 share 값은 먼저 share-access 호출)

---

## 11단계: 사용자 스토리 10 - 메인 공지사항 (P3)

- [X] T051 [P] [US10] `board/NoticeIntegrationTest`: 관리자만 쓰기, 일반 회원·블로그장 403, 다른 관리자 수정·삭제 성공, 공지 알림 켠 회원만 NOTICE 알림(설정 행 없으면 켜짐), 관리자에게는 안 감, 공지 목록·상세, 카테고리·태그 무시 (US10, D-100 #19)
- [X] T052 [US10] `board/application/NoticeService.java`와 `board/api/NoticeController.java`(목록·쓰기·이미지)를 만들고, 공지 수정·삭제는 `PUT·DELETE /api/posts/{id}`가 관리자를 받게 한다
- [X] T053 [US10] 화면 `static/notices/index.html`·`post.html`·`write.html` + `js/board-notice*.js`, `/notices/**` forward와 og 채움, 상단 메뉴에 "공지사항" 링크

---

## 12단계: 정리 작업과 다듬기 (Polish)

- [X] T054 `board/application/BoardDailyTasks.java`를 `DailyCleanupJob`에 더한다(삭제 30일 글·댓글 정리, 연결 안 된 이미지 1일 표시, 이미지 파일 30일 삭제, 조회 기록 7일 정리)와 `board/BoardDailyTasksIntegrationTest` (FR-013, SC-012, D-100 #4)
- [X] T055 [P] `contract/OpenApiConformanceTest`에 board-api.yaml 경로·메서드 대조와 "계약에 없는 API 없음"을 더한다
- [X] T056 [P] `board/BoardSecurityTest`: 글·댓글·검색·피드·태그·공지 응답 전체와 로그에 이메일·전화번호·이름 없음, CSRF 없는 쓰기 403, 공격 문자열 모음을 제목·댓글·태그·검색어에 넣어도 응답이 HTML로 해석되지 않는 JSON 문자열 (SC-002, SC-011)
- [X] T057 [P] `perf/PostResponseTimeTest`: 글 5,000개로 목록·검색·피드가 2초 안 (SC-001)
- [X] T058 [P] `js/api.js`에 5초 중단(`AbortController`)과 다시 시도 안내를 더한다 (FR-070, D-48)
- [X] T059 `local/seed.sql`에 글·댓글·카테고리·태그 예시를 더하고, 화면을 360px·PC에서 확인한다 (SC-013)
- [X] T060 quickstart.md "확인 결과"를 채우고 README의 기능 목록을 갱신한다

---

## 의존 관계와 실행 순서

- 1단계 → 2단계 → US1(MVP) → 나머지 스토리. US2·US3·US4·US5·US6·US7은 US1 뒤에 서로 독립이다. US8·US9는 상세 화면(T022) 뒤, US10은 US1·US4 뒤.
- 12단계는 모든 스토리 뒤.
- 같은 파일(`blog/index.html`, `blog/post.html`, `board-post.js`)을 고치는 작업은 차례로 한다.

## 구현하며 바뀐 점 (2026-10-08)

- 게시판 테이블은 JPA 엔티티 없이 `JdbcTemplate`으로 읽고 쓴다(T008). `board/domain`은 만들지 않았다. 목록·검색이 대부분 여러 테이블을 잇는 SQL이라서다.
- 컨트롤러는 계획보다 적게 묶었다. 이미지 올리기는 `PostController`, 좋아요는 `CommentController`, 검색·최근 검색어·태그 글·피드는 `DiscoveryController`, og 채움은 `PostOgPageController`, 공지·검색·태그 화면 forward는 `NoticePageController`에 있다. 공지 쓰기는 `PostService.createNotice`가 맡는다.
- 화면 스크립트 이름: `board-common.js`, `board-feed.js`, `board-post.js`, `board-write.js`, `board-search.js`, `board-tag.js`, `board-notices.js`.
- 계약 경로는 16개다(계획의 17개는 셈 착오).
- 글 쓰기에서 다른 블로그·없는 카테고리는 400 `VALIDATION_FAILED`(field categoryId), 좋아요 트래픽 제한은 001과 같은 429 `RATE_LIMITED`로 맞췄다(계약 고침).
- 통합 검색 관련도순은 맞은 조건 수(제목·태그·닉네임)로 정렬한다. MySQL이 MATCH 점수와 정수를 더하면 범위 오류를 내서다.
- 조회 기록은 글 행을 먼저 잠그고 넣는다(동시 조회 교착 방지).
