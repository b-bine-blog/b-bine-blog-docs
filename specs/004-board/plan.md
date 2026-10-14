# 구현 계획 (Implementation Plan): 게시판(글·댓글·검색·피드·공유)

**브랜치**: `004-board` | **날짜**: 2026-10-08 | **명세**: [spec.md](spec.md)

**입력**: `specs/004-board/spec.md` (확인 필요 항목 0개, D-100까지 반영)

## 요약 (Summary)

블로그 멤버가 마크다운 에디터로 글을 쓰고(이미지·태그·카테고리), 방문자가 목록·상세·태그·통합 검색·메인 피드로 글을 읽는다. 회원은 댓글·답글·좋아요를 남기고, 관리자는 메인 공지를 올린다.
001·002와 같은 Spring Boot 앱에 `board` 패키지를 더한다.
- 본문: 읽을 때마다 서버가 commonmark로 HTML로 바꾸고 jsoup으로 거른다(R-01).
- 글 상세 화면: 서버가 og 태그만 채운 HTML을 내려준다(R-12).
- ERD: Crowfoot 문서 654의 게시판 테이블을 그대로 쓴다. **DB 구조 변경은 없고**, 설명 문구와 요구사항만 D-100에 맞춰 Crowfoot에서 고쳤다(R-17).

## 기술 맥락 (Technical Context)

**언어/버전**: Java 21, Spring Boot 3.5.16

**주요 의존성**: 001·002와 같음 + `org.commonmark:commonmark:0.24.0`, `commonmark-ext-gfm-tables`, `commonmark-ext-gfm-strikethrough`, `org.jsoup:jsoup:1.18.1`. 화면 에디터는 Toast UI Editor 3.2.2를 `static/vendor/`에 넣는다(R-02).

**저장소**: MySQL 8(Crowfoot 문서 654), 글 이미지는 `FileStorage` → 서버 디스크(D-75)

**테스트**: JUnit 5, MockMvc, Testcontainers MySQL 8.0, `MutableClock`, `IntegrationTestBase`·`BlogTestBase`

**대상 플랫폼**: Linux 서버 1대(1차), PC·모바일 브라우저

**프로젝트 종류**: 웹 서비스(REST API + 정적 화면, 단일 Spring Boot 앱)

**성능 목표**: 메인 피드·목록·검색은 1초 목표, 2초 이내다(SC-001). 화면은 5초가 넘으면 중단하고 다시 시도하라고 안내한다.

**제약**:
- 서버에 상태를 두지 않는다. 조회 기록·공유 링크는 DB와 쿠키로 판단한다.
- 숫자 규칙은 모두 `board.*` 설정값으로 둔다(D-68).
- 응답에는 닉네임·프로필 사진만 넣는다(D-22).
- 본문만 innerHTML로 넣는다(D-64).

**규모/범위**:
- API 26개(경로 16개). 계약은 [contracts/board-api.yaml](contracts/board-api.yaml)에 있다.
- 화면 8개: 글쓰기·수정, 글 상세, 블로그 글 목록(블로그 홈에 붙임), 카테고리 관리(운영 화면에 붙임), 통합 검색, 메인 피드(메인에 붙임), 태그 글 목록, 공지 목록·상세·쓰기
- 테이블 14개를 쓰고, 새로 만드는 테이블은 없다.

**다른 기능과 나눈 범위**:
- 팔로우·차단(003): 004는 `follows`·`user_blocks`를 읽기만 한다(피드 팔로우 탭, 검색·피드·댓글의 차단 숨김). 만들기·취소 API와 화면은 003이 만든다. 그래서 003이 붙으면 004의 규칙이 그대로 동작한다.
- 알림(003): 004는 `NotificationWriter`로 쓰기만 하고, 알림함·폴링·설정 화면은 003이 만든다. 설정이 꺼져 있으면 쓰지 않는 확인은 004에서 이미 동작한다(`notification_settings`).
- 관리자(005): 글·댓글 숨김·삭제, 30일 안 복구(FR-013, ADM-03)는 005가 만든다. 004는 `status`·`deleted_at`만 남긴다.
- 신고(003): 글·댓글 신고 버튼은 003에서 붙인다.

## 헌장 확인 (Constitution Check)

*Phase 0 전 확인, Phase 1 설계 후 다시 확인함.*

| 원칙 | 이 계획에서 지키는 방법 | 결과 |
|---|---|---|
| I. 보안 우선 | 서버에서 마크다운 → HTML → jsoup 허용 목록으로 거른다(R-01). 본문만 innerHTML로 넣는다. 업로드는 확장자·MIME·시그니처를 확인하고 재인코딩해 EXIF를 지운다(R-03). 남이 올린 이미지는 연결하지 않는다. 검색은 바인딩 파라미터와 구절 검색으로 한다(R-13). 에디터는 자체 서버에서 내보내 CSP `'self'`를 지킨다(R-02). og 값은 이스케이프한다(R-12). 상태 변경에는 CSRF가 있다 | 통과 |
| II. 블로그별 역할 서버 확인 | 쓰기·수정·삭제·카테고리·댓글 삭제를 요청마다 `BlogPermissionService`로 확인한다(R-04). 블로그를 떠난 작성자의 수정·삭제는 거부한다(D-100 #1). 권한표는 data-model에 있다. SC-004 테스트가 있다 | 통과 |
| III. 개인정보 서버에서 가림 | `Author` DTO는 닉네임·사진만 담는다(R-05). `BoardSecurityTest`가 응답·로그에서 이메일·전화번호를 찾는다(SC-011) | 통과 |
| IV. 서버에 상태를 두지 않음 | 조회 기록은 DB 유니크로 한 번만 센다(R-10). 좋아요는 DB 유니크로 하나만 남는다(R-09). 정리는 ShedLock으로 한 번만 돈다. 이미지는 `FileStorage`에 둔다. 좋아요·조회의 트래픽 제한만 001과 같이 `RateLimiter`(서버 메모리, 이중화 때 교체)를 쓴다 | 통과(001 R-08과 같은 예외) |
| V. 명세와 결정이 먼저 | 모든 API에 FR·D 번호가 있다. 문서에 없어 기본값으로 둔 것은 research에 *가정*으로 표시하고 아래에 모았다. DB 설명과 요구사항은 Crowfoot 문서에서 먼저 고쳤다 | 통과(가정 보고) |
| VI. 단순하게 시작 | 새 테이블이 없다. 피드는 볼 때마다 쿼리한다(D-73). 썸네일 파일을 따로 만들지 않는다. 템플릿 엔진 없이 og 자리만 바꾼다 | 통과 |

**설계 후 다시 확인**: data-model과 contracts에서 새로 생긴 위반은 없다. Crowfoot 변경은 설명 문구뿐이다.

## 확인할 가정 (문서에 없어 기본값으로 둔 것)

사용자가 "순서대로 전부 다만들어"(2026-10-08)라고 해서 아래 기본값으로 진행한다. 다르면 고친다.

1. 통합 검색 "전체"는 블로그 앞 5개(전체 개수 표시)와 글 번호 페이지를 함께 보여준다(R-13).
2. 구독 탭에는 구독자가 볼 수 있는 일부 공개 블로그의 글도 넣는다. 002에서 일부 공개 블로그는 구독자도 볼 수 있게 했기 때문이다(R-04).
3. 조회 기록은 7일 뒤 지운다(R-10). 하루 한 번 판단에만 쓰기 때문이다.
4. 답글은 답한 대상에게만 알리고, 글 작성자에게 "내 글에 댓글" 알림을 또 보내지 않는다(data-model).
5. 댓글은 최상위 20개씩 페이지로 보여주고, 답글은 한 번에 모두 보여준다(R-08).
6. 카테고리 이름은 블로그 안에서 겹치지 않게 한다(R-06).
7. 공지 알림은 한 번의 INSERT ... SELECT로 넣는다. 회원이 많아지면 나눠 넣는다(R-15).

## 프로젝트 구조 (Project Structure)

### 문서 (이 기능)

```text
specs/004-board/
├── spec.md
├── clarify-questions.md
├── plan.md              # 이 파일
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── board-api.yaml
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### 소스 코드 (저장소 루트, 001·002에 더하는 것)

```text
src/main/java/com/mainblog/
├── common/
│   ├── config/          # BoardProperties (board.*), AppProperties (app.base-url)
│   ├── markdown/        # MarkdownRenderer(commonmark + jsoup Safelist), MarkdownText(요약·첫 이미지·이미지 이름 추출)
│   └── notification/    # NotificationType에 POST_COMMENT, COMMENT_REPLY, POST_LIKE, POST_DELETED, NOTICE 추가
├── board/
│   ├── api/             # PostController, CategoryController, PostImageController, CommentController, LikeController,
│   │                    # TagPostController, SearchController, RecentSearchController, FeedController, NoticeController,
│   │                    # PostPageController(/blog/{주소}/posts/{id}, /notices/{id} og 채움, 글쓰기 화면 forward)
│   ├── application/     # PostService, PostQueryService, PostVisibility, PostPolicy(권한), AuthorView,
│   │                    # CategoryService, PostTagService, PostImageService, CommentService, CommentQueryService,
│   │                    # LikeService, ViewCountService, SearchService, RecentSearchService, FeedService,
│   │                    # NoticeService, OgTagRenderer, BoardDailyTasks
│   └── domain/          # Post, Category, PostTag, PostImage(images), Comment, PostLike, RecentSearch (+ Repository, enum)
└── batch/
    └── DailyCleanupJob.java   # BoardDailyTasks 단계 추가(글 30일 정리 → 댓글 정리 → 연결 안 된 이미지 표시 → 이미지 파일 삭제 → 조회 기록 정리)

src/main/resources/
├── application.yml      # board.*, app.base-url, multipart 11MB (data-model "설정값")
└── static/
    ├── index.html       # 메인: 피드 탭(최신·인기·구독·팔로우) + 블로그 목록 + 검색창
    ├── search.html      # 통합 검색(분류바·정렬·최근 검색어)
    ├── tags/index.html  # /tags/{이름} 태그 글 목록
    ├── blog/index.html  # 블로그 홈에 글 목록·카테고리·글쓰기 버튼 추가
    ├── blog/post.html   # 글 상세(<!--OG--> 자리, 본문·댓글·좋아요·공유)
    ├── blog/write.html  # 글쓰기·수정(Toast UI, 자동 저장, 로그인 연장)
    ├── blog/manage.html # 카테고리 관리 탭 추가
    ├── notices/         # index.html(목록), post.html(상세), write.html(관리자)
    ├── img/og-default.png
    ├── vendor/toastui/  # toastui-editor-all.min.js, toastui-editor.min.css
    └── js/board-*.js, api.js(5초 중단)

src/test/java/com/mainblog/
├── board/               # 사용자 스토리별 통합 테스트, BoardSecurityTest, 정책 단위 테스트
├── common/              # MarkdownRenderer(XSS 사례 모음), MarkdownText 단위 테스트
├── contract/            # OpenApiConformanceTest에 board-api.yaml 추가
└── perf/                # PostResponseTimeTest(글 5,000개)
```

**구조 결정**: 게시판은 메인 공지와 블로그가 같이 쓰는 공통 모듈이므로(FR-001) `blog`가 아니라 `board` 패키지에 둔다. 블로그 권한·열람 판단은 002의 `BlogPermissionService`·`BlogAccessPolicy`를 부른다. 마크다운 변환은 og 요약에도 쓰므로 `common/markdown`에 둔다.

## 구현 전에 할 일

1. **Crowfoot DB 반영**: 문서 654의 설명 변경을 연결 DB에 반영할지 사용자 결정을 받는다(R-17). 앱과 테스트는 저장소의 `schema.sql`을 쓰므로 구현은 막히지 않는다.
2. **병합 순서**: 004 브랜치는 `002-blog-management` 위에 있다. PR #1 → #2 → #3 → 004 PR 순서로 병합한다.
3. **설정값**: `.env.example`과 `local/start.sh`·`start.bat`에 `APP_BASE_URL`을 넣는다(og 절대 주소).

## 복잡도 기록 (Complexity Tracking)

헌장 위반 없음. 트래픽 제한의 서버 메모리 사용은 001 R-08에서 이미 받아들인 예외와 같다.
