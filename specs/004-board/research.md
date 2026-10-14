# 004 게시판 조사 (Phase 0 Research)

**날짜**: 2026-10-08 | **명세**: [spec.md](spec.md) | **계획**: [plan.md](plan.md)

명세의 확인 필요 항목 21개는 D-100으로 모두 정해졌다. 001(R-01~R-14)과 002(R-01~R-17)에서 정한 기술은 그대로 쓰고, 여기서는 004에서 새로 생기는 구현 방식만 정한다.
규칙 값(글자 수·개수·기간)은 명세·결정을 따르고 여기서 새로 정하지 않는다. "*가정*"으로 표시한 것은 문서에 없어 구현 기본값으로 둔 것이며, 사용자 확인 뒤 바뀔 수 있다.

---

## R-01 마크다운 → HTML → 걸러내기

- **결정**: 글을 읽을 때마다 서버에서 `commonmark-java`(0.24.0, 표·취소선 확장 포함)로 마크다운을 HTML로 바꾸고, `jsoup`(1.18.1)의 허용 목록(`Safelist`)으로 걸러 `contentHtml`로 응답한다. DB에는 마크다운 원문만 둔다(`posts.content`).
- **허용 목록**: `Safelist.relaxed()`를 바탕으로
  - 허용 태그: 제목(h1~h6), 문단, 목록, 인용, 코드(pre, code), 표, 강조, 링크(a), 이미지(img), hr, br, del
  - 링크: `href`는 http·https·mailto만 허용한다. `rel="nofollow noopener noreferrer"`를 붙이고 `target`은 뺀다.
  - 이미지: `src`는 `/files/`로 시작하는 우리 서버 파일과 http·https만 허용한다(`javascript:`, `data:` 금지).
  - `style`, `on*` 이벤트 속성, `script`, `iframe`, `object`, `form`은 모두 지운다.
- **원문 HTML**: 마크다운 안의 HTML은 commonmark가 그대로 통과시키고 jsoup이 걸러낸다. 그래서 `<b>`는 남고 `<script>`, `onerror`는 사라진다(인수 시나리오 1-5).
- **화면**: 본문 `contentHtml`만 `innerHTML`로 넣고, 제목·닉네임·댓글·태그·검색어는 모두 `textContent`로 넣는다(FR-006, D-64).
- **글자 수**: 5,000자는 마크다운 원문의 `String.codePointCount`로 센다(공백·기호 포함, D-92). 이모지 한 개는 1자다. *가정*
- **이유**: SEC-06, D-64(서버 변환 + jsoup), D-74(마크다운 저장). 저장 시점이 아니라 읽을 때 걸러야 허용 목록을 바꿔도 예전 글에 바로 적용된다.
- **검토한 다른 안**: flexmark(기능은 많지만 의존성이 크다), 저장할 때 HTML도 저장(컬럼이 없고 허용 목록 변경이 반영되지 않는다), 화면 DOMPurify(D-64가 서버로 정했다).

## R-02 에디터 (Toast UI Editor)

- **결정**: Toast UI Editor 3.2.2의 배포 파일(`toastui-editor-all.min.js`, `toastui-editor.min.css`)을 `static/vendor/toastui/`에 넣어 우리 서버에서 내보낸다. 마크다운 모드, 미리보기 탭, 기본 툴바를 쓰고, 이미지 버튼은 `addImageBlobHook`으로 우리 업로드 API를 부른다.
- **이유**: D-74. CSP가 `script-src 'self'`라 외부 CDN을 열지 않아도 된다(SEC-12). 라이선스는 MIT다.
- **미리보기**: 에디터 미리보기는 화면에서만 보이는 것이고, 저장된 글의 표시는 언제나 R-01의 서버 변환 결과다.
- **자동 저장**: 입력이 멈추고 1초 뒤 `localStorage`의 `draft:{blogId}`(수정은 `draft:post:{postId}`)에 제목·본문·태그·카테고리를 저장한다. 저장에 성공하면 지운다. 다른 기기에서는 이어 쓸 수 없다(FR-014).
- **로그인 연장**: 글쓰기 화면은 입력이 있으면 5분마다 `POST /api/auth/extend`를 부르고, 만료 5분 전에 "로그인을 연장할까요?" 창을 띄운다(SEC-04, D-62, 001 `auth.extend-interval`).

## R-03 글 이미지 업로드와 연결

- **결정**:
  - `POST /api/blogs/{blogId}/images`(공지는 `POST /api/notices/images`)로 multipart 파일을 여러 장 받는다.
  - 각 파일은 001의 `ImageValidator`(확장자·MIME·시그니처)와 `ImageSanitizer`(재인코딩, EXIF 제거)를 거친다. 그다음 `FileStorage`에 UUID 이름으로 저장한다.
  - `images` 행은 `owner_type = 'POST'`, `owner_id = NULL`로 만들고, 응답으로 `/files/{저장 이름}` 주소를 돌려준다.
- **한도**:
  - 장당 3MB(`board.image.max-size`)
  - 한 번에 보내는 용량 10MB(`board.image.max-request-size`)
  - `spring.servlet.multipart.max-request-size`는 10MB에 multipart 여유를 더한 11MB로 올리고, 넘으면 001·002와 같이 400 `FILE_TOO_LARGE`로 응답한다(구현 때 기존 처리에 맞춤)
  - 한 글에 10장(`board.image.max-per-post`)
- **글과 연결**:
  - 글을 저장·수정할 때 본문 마크다운에서 `/files/{이름}` 이미지 주소를 모은다.
  - 그 이름 가운데 "이 회원이 올렸고 소속이 없거나 이 글인" 이미지만 `owner_id = 글 번호`로 바꾼다. 남이 올린 이미지 이름을 넣어도 연결되지 않는다.
  - 서로 다른 이미지가 10장을 넘으면 400 `POST_IMAGE_LIMIT`이다.
  - 수정 때 본문에서 빠진 이 글의 이미지는 `owner_id = NULL`로 되돌려 R-11 정리 대상으로 만든다.
- **업로드 권한**:
  - 블로그 글 이미지는 그 블로그에 글을 쓸 수 있는 사람(멤버, 정지 아님)만 올린다.
  - 공지 이미지는 메인 관리자만 올린다.
  - 11번째 장은 글 저장 때 막고, 업로드 때도 "업로드 요청 안의 파일 수 > 10"이면 막는다.
- **이유**: FR-029~FR-035, SEC-08, D-75. 업로드를 글 저장과 나누면 에디터가 이미지를 바로 본문에 넣을 수 있다.
- **목록의 첫 사진**: 목록·미리보기에 쓰는 "첫 사진"은 본문에서 처음 나오는 이미지 주소로 정한다. 저장된 글의 본문을 읽어 서버가 `thumbnailUrl`로 내려준다(D-100 #7). 썸네일 파일은 따로 만들지 않는다(6.3).

## R-04 글 권한과 보이는 글 규칙

- **쓰기**: `BlogPermissionService.require(blogId, MEMBER)`를 쓴다(멤버 + 정지 아님 + ACTIVE·CLOSING). 메인 관리자(role = ADMIN)는 블로그 멤버가 될 수 없으므로 자연히 403이다. 그래도 서비스에서 `ADMIN_NOT_ALLOWED`로 한 번 더 막는다(D-90).
- **수정**: 작성자 본인이면서 지금 그 블로그의 멤버여야 한다. 블로그를 떠난 뒤에는 수정할 수 없다(D-100 #1). 기존 `canEditPost`를 쓴다.
- **삭제**:
  - 누가 지울 수 있는지
    - 작성자 본인(지금 멤버일 때만, D-100 #1)
    - 그 블로그의 `POST_MANAGE` 권한자(블로그장, 권한 받은 부블로그장)
    - 메인 관리자
  - 남이 지우면 끌 수 없는 `POST_DELETED` 알림을 작성자에게 보낸다(FR-011).
- **보이는 글** (`PostVisibility` 한 곳에서 SQL 조건을 만든다):
  - 글 조건: `posts.status = 'VISIBLE'`
  - 블로그 글이면 블로그 조건: `blogs.status IN ('ACTIVE','CLOSING')`
  - 블로그 상세·목록 열람: 002 `BlogAccessPolicy.canView`
    - PUBLIC: 누구나
    - LINK: 멤버·구독자·유효한 공유 쿠키
    - PRIVATE: 멤버
    - 정지 중이면 403
  - 메인 피드(최신·인기)·검색·태그 목록: `visibility = 'PUBLIC' AND hidden = false`만 넣는다(FR-058, FR-061)
  - 구독 탭: 그 블로그를 볼 수 있는 경우만 넣는다
    - PUBLIC이면 넣는다
    - LINK는 구독자도 볼 수 있으므로 넣는다(002 R-06과 같음). *가정*
    - PRIVATE는 멤버일 때만 넣는다
- **없는 글과 못 보는 글**: 둘 다 404 `POST_NOT_FOUND`로 응답해 있는지 드러내지 않는다(002와 같음).

## R-05 작성자 표시

- **결정**: 응답의 작성자는 `{ id, nickname, profileImageUrl, state }`이고 `state`는 셋 중 하나다.
  - `ACTIVE`
  - `LEFT_BLOG`: `posts.author_left = true`. 닉네임 자리에 "탈퇴한 계정"을 넣고 `id`·사진은 비운다.
  - `WITHDRAWN`: `users.status = 'WITHDRAWN'`. "탈퇴한 회원"을 넣는다.
- **우선순위**: 회원탈퇴가 블로그 탈퇴보다 앞선다.
- **댓글**: 블로그를 떠나도 닉네임을 그대로 쓰고(D-100 #1), 회원탈퇴면 "탈퇴한 회원"이다(D-100 #2).
- **개인정보**: 이메일·이름·전화번호는 어느 DTO에도 없다(FR-073, D-22). `BoardSecurityTest`가 응답과 로그를 검사한다.

## R-06 카테고리

- **결정**:
  - `categories` 테이블을 쓴다. 블로그당 최대 30개(`board.category.max-count`), 이름 1~30자(`board.category.name-max-length`)이고, 블로그 안에서 이름이 겹치면 409 `CATEGORY_DUPLICATE`이다. *가정*: DB 유니크 없이 서비스에서 블로그 행을 잠그고 확인한다.
  - 추가·수정·삭제·순서 변경은 `@blogAuth.has(#blogId, 'POST_MANAGE')`가 확인한다.
  - 지우면 그 카테고리의 글을 `category_id = NULL`(미분류)로 바꾼 뒤 지운다(D-100 #8).
  - 글을 쓸 때 고른 카테고리는 같은 블로그 것만 받는다.
- **목록 필터**: `categoryId`를 주면 그 카테고리 글만 보이고, `categoryId=0`이면 미분류 글만 보인다.

## R-07 태그

- **결정**: 002의 `TagNormalizer`와 `tags` 찾기·만들기를 그대로 쓰고, 연결은 `post_tags`에 둔다. 최대 10개(`board.tag.max-count`), 1~20자이며 금칙어는 없다(D-96).
- **수정할 때**: 태그 목록 전체를 바꾼다(지우고 다시 넣기).
- **태그 목록 API**: `GET /api/tags/{name}/posts`는 R-04의 공개 글 조건과 차단 조건을 쓰고, 최신순 번호 페이지로 응답한다.

## R-08 댓글

- **구조**: 최상위 댓글은 `parent_id = NULL`, 답글은 `parent_id = 최상위 댓글`이다.
  - 답글에 답하면 `parent_id`는 그 답글의 부모로 두고, `reply_to_user_id`에 그 답글의 작성자를 넣는다(D-100 #10, D-87).
  - 최상위 댓글에 답하면 `reply_to_user_id`는 그 댓글의 작성자다.
- **목록**: 최상위 댓글은 작성순 페이지로(`board.comment.page-size` 기본 20) 보이고, 각 최상위 댓글의 답글은 모두 작성순으로 함께 내려준다. *가정*: 댓글이 많지 않아 답글은 한 번에 내려준다.
- **삭제**:
  - 답글이 남아 있는 최상위 댓글은 `status = 'DELETED'`, 내용 비공개로 바뀐다. "삭제된 댓글입니다" 자리로 응답한다.
  - 답글이 없으면 목록에서 뺀다.
  - 마지막 답글이 지워지면 "삭제된 댓글입니다" 자리도 응답에서 빠진다(D-100 #3). 삭제 상태인 최상위 댓글은 "보이는 답글이 있을 때만" 응답에 넣는 조회 규칙으로 처리하고, 행은 30일 뒤 정리한다.
- **권한**:
  - 수정은 작성자만 하고, 수정하면 `edited = true`이다.
  - 삭제는 작성자, 그 블로그의 `POST_MANAGE` 권한자가 한다(D-100 #11).
  - 메인 관리자의 숨김·삭제는 005(ADM-03)에서 한다.
  - 댓글 쓰기는 그 글을 볼 수 있는 로그인 회원이다. 공유 링크로 일부 공개 블로그 글을 보는 회원도 포함한다(D-100 #9).
  - 메인 관리자와 정지 중인 회원은 쓸 수 없다. 공지에는 댓글을 달 수 없다(D-100 #19).
- **차단**: 보는 사람이 차단한 회원의 댓글은 응답에서 뺀다. 둘이 그 블로그의 멤버이면 보인다(FR-045). 차단 관계는 `user_blocks`를 읽기만 한다. 만드는 쪽은 003이다.

## R-09 좋아요

- **결정**:
  - 누르기·취소를 오가는 토글 하나(`PUT /api/posts/{postId}/like`)다. 이미 있으면 지우고, 없으면 `INSERT IGNORE`로 만든다.
  - 동시 요청은 `uk_post_likes_user_id_post_id`가 하나만 남긴다(SC-006).
  - `posts.like_count`는 `+1`·`-1`을 바꾼 행 수에 맞춰서만 반영한다(`UPDATE posts SET like_count = like_count + ? WHERE id = ?`).
  - 응답은 `{ liked, likeCount }`이다.
- **트래픽 제한**: 회원당 1분에 30번(`board.like.rate-limit`, `board.like.rate-window`, D-100 #12)이다. 001의 `RateLimiter`(서버 메모리)를 쓰고, 넘으면 429 `RATE_LIMITED`(001과 같은 코드)이다. 이중화 때 공유 저장소로 바꾸는 점은 001 R-08과 같다.
- **알림**: 처음 누를 때 글 작성자에게 `POST_LIKE`를 보낸다. `event_key = POST_LIKE:{postId}:{userId}`라서 취소 후 다시 눌러도 `INSERT IGNORE`로 다시 만들어지지 않는다(D-100 #13). 자기 글이면 보내지 않는다.

## R-10 조회수

- **누구로 셀지** (`viewer_key`):
  - 회원: `U:{회원 번호}`
  - 비회원: `G:{쿠키 값}`. 쿠키 `VID`는 128비트 무작위 hex 32자이고, HttpOnly, SameSite=Lax, 1년(`board.view.guest-cookie-max-age`)이다. 없으면 처음 볼 때 굽는다(D-100 #20).
- **세는 방법**: `INSERT IGNORE INTO post_views (post_id, viewer_key, view_date)`의 결과가 1행일 때만 `view_count + 1`이다. 같은 날 두 탭에서 동시에 열어도 유니크 제약으로 한 번만 센다(D-77, SC-005). 날짜는 `Clock`(Asia/Seoul)의 오늘이다.
- **세지 않는 것**:
  - 작성자 본인(D-100 #20)
  - User-Agent에 `bot`·`crawler`·`spider`·`slurp`·`preview`가 들어간 요청. 목록은 `board.view.bot-user-agents` 설정값이다.
  - 같은 IP가 1분에 글 60개를 넘게 연 경우(`board.view.ip-limit`, `RateLimiter`, D-100 #21)
  - 이때도 글은 정상으로 보인다.
- **기록 보관**: 조회 기록은 "같은 날 한 번" 판단에만 쓰므로 7일(`board.view.retention`)이 지난 행을 04:00 정리에서 지운다. *가정*: 스키마에 보관 기간이 "미정"으로 되어 있어 기본값을 두었다.

## R-11 삭제·보관·정리 (04:00)

- **삭제 표시**: 글·댓글 삭제는 `status = 'DELETED'`, `deleted_at`, `deleted_by`(글)를 채운다. 화면에서는 바로 사라진다(FR-013). 복구는 005 관리자 기능이다.
- **`BoardDailyTasks`**: 001의 `DailyCleanupJob`(ShedLock)에 단계를 더한다.
  1. 삭제 30일 지난 글: 그 글의 이미지는 `deleted_at`을 채우고, 글 행을 지운다. 댓글·좋아요·조회·태그 연결은 FK CASCADE로 함께 지워진다(`board.purge-after`).
  2. 삭제 30일 지난 댓글을 지운다. 이때 답글이 남은 최상위 댓글은 답글이 모두 정리될 때까지 남긴다.
  3. 연결 안 된 이미지(`owner_type = 'POST' AND owner_id IS NULL AND deleted_at IS NULL`)가 올린 지 1일(`board.image.orphan-after`)이 지나면 `deleted_at`을 채운다(D-100 #4).
  4. `deleted_at`이 30일 지난 글 이미지는 파일과 행을 지운다. 프로필·대표 이미지 정리와 같은 방식이다.
  5. 7일 지난 조회 기록을 지운다.
- **블로그 폐쇄**: 블로그 폐쇄 뒤 30일 정리는 002 `BlogPurgeService`가 이미 글·댓글·이미지·카테고리를 지운다.

## R-12 글 상세 화면과 미리보기(og 태그)

- **결정**:
  - `GET /blog/{주소}/posts/{postId}`는 `PostPageController`가 처리한다. 시작할 때 읽어 둔 `static/blog/post.html`의 `<!--OG-->` 자리에 og·twitter 메타 태그를 넣어 HTML로 응답한다.
  - 모든 값은 HTML 속성용으로 이스케이프한다.
  - 본문은 넣지 않는다. 본문은 화면 스크립트가 API로 받아 그린다(D-66).
  - 공지 상세 `/notices/{postId}`도 같은 방식이다.
- **메타 값**:
  - `og:url`: 글 주소
  - `og:title`: `제목 - 닉네임`
  - `og:description`: R-01 변환 결과에서 글자만 뽑아 공백을 정리한 앞 100자(`board.og.summary-length`, D-100 #14)
  - `og:image`: 아래 순서로 정하고, 절대 주소로 쓴다(`app.base-url` 설정값)
    1. 본문 첫 이미지
    2. 블로그 대표 이미지
    3. 사이트 기본 이미지(`/img/og-default.png`, D-100 #15)
  - 순서는 주소 → 제목(닉네임) → 이미지다(D-59).
- **못 보는 글**: 404 화면이 아니라 사이트 기본 미리보기(사이트 이름·기본 이미지)로 응답한다.
  - 일부 공개 블로그의 글은 주소의 `share` 값이 유효한 링크일 때만 글 미리보기를 채운다(D-100 #6).
  - 비공개 블로그, 삭제된 글, 없는 글은 기본 미리보기다.
  - 그래도 화면 스크립트가 API로 확인해 "볼 수 없는 글" 안내를 띄운다.
- **공유 버튼** (`navigator.clipboard`, 실패하면 입력 칸을 선택해 둔다):
  - PUBLIC: 글 주소를 복사한다.
  - LINK: `글 주소?share={유효한 공유 값}`을 복사한다. 공유 값은 이 블로그의 멤버가 볼 때 `GET /api/blogs/{blogId}/share-link`로 받는다. 멤버가 아니면 지금 주소의 `share` 값을 쓴다(D-100 #5).
  - PRIVATE: 버튼을 숨긴다(FR-047).
  - 공유 수는 세지 않는다(FR-051).
- **share 값 처리**: 주소에 `share`가 있으면 화면이 먼저 002의 `POST /api/blogs/share-access`를 불러 쿠키를 받고 글을 읽는다.

## R-13 통합 검색

- **분류(`type`)**: 아래 다섯 가지이고, 정렬(`sort`)은 `RELEVANCE`(기본)·`LATEST`·`POPULAR`, 페이지 크기는 10·20·30이다.
  - `ALL`(기본)
  - `BLOG`: 이름·소개, ngram
  - `TITLE`: 글 제목, ngram
  - `TAG`: 정확히 일치
  - `NICKNAME`: 정확히 일치, 탈퇴 회원 제외
- **`ALL` 응답**: `blogs`(블로그 앞 5개와 전체 개수)와 `posts`(글 제목·태그·닉네임 중 하나라도 맞는 공개 글, 번호 페이지)를 함께 준다. 화면은 "블로그 더 보기"로 `type=BLOG`를 연다. *가정*: 문서에 통합 결과를 어떻게 섞어 넘기는지 없어, 블로그는 미리보기, 글은 페이지로 나눴다.
- **관련도**:
  - 글: `MATCH(title) AGAINST(? IN BOOLEAN MODE)` 점수에, 태그 일치 +1, 닉네임 일치 +1을 더한다.
  - 블로그: 002 R-07의 점수다.
  - 값이 같으면 최신순이다.
- **인기순**: 글은 `like_count DESC, created_at DESC`, 블로그는 `member_count DESC, created_at DESC`이다(D-89).
- **검색어**: 앞뒤 공백을 빼고 2~20자이며, 글자·숫자가 하나도 없으면 400 `SEARCH_KEYWORD_INVALID`이다.
  - ngram 검색어는 002 R-07처럼 큰따옴표 구절(`"..."`)로 감싸 바인딩 파라미터로 넘긴다. 연산자 문자는 지운다.
- **제외**:
  - 비공개·일부 공개·숨김 블로그와 그 글, 숨김·삭제 글, 폐쇄된 블로그
  - 보는 사람이 차단한 회원의 글. 단, 같은 블로그 멤버이면 넣는다.
  - 결과 개수에도 넣지 않는다(D-100 #16).
- **최근 검색어**:
  - 로그인 회원이 검색하면 `recent_searches`에 넣는다. 같은 검색어가 있으면 `searched_at`만 바꿔 맨 앞으로 옮긴다(D-100 #17).
  - 10개(`board.search.recent-max`)를 넘는 오래된 행은 지운다.
  - 비회원은 저장하지 않는다.
  - API: 목록, 하나 삭제, 전체 삭제.

## R-14 메인 피드

- **최신 탭·인기 탭** (`GET /api/feed?tab=LATEST|POPULAR`):
  - 대상: 공개·숨기지 않은 블로그의 보이는 글, 그리고 차단 제외
  - 정렬: 최신은 `created_at DESC, id DESC`, 인기는 `like_count DESC, created_at DESC, id DESC`(D-89)
  - 넘기기: 번호 페이지(10·20·30)이고, 비회원도 볼 수 있다
- **구독 탭** (`tab=SUBSCRIBED`):
  - 대상: 구독한 블로그의 최근 30일(`board.feed.recent-days`) 글이며, R-04의 구독 탭 규칙을 따른다
  - 넘기기: 한 번에 20개(`board.feed.page-size`)이고, 화면은 "더 보기"를 누르면 이어서 받는다(D-100 #18). 커서는 `(created_at, id)`이다
- **팔로우 탭** (`tab=FOLLOWING`): `follows`를 읽어 팔로우한 회원이 볼 수 있는 블로그에 쓴 최근 30일 글을 같은 방식으로 보여준다. 팔로우 만들기·취소는 003이 만든다. 004는 `follows`를 읽기만 하므로 003이 붙으면 그대로 동작한다.
- **비회원**: 구독·팔로우 탭은 401이다.
- **바로 반영**: 볼 때마다 쿼리로 모으므로 삭제·차단·비공개 전환이 다음 조회에 바로 반영된다(D-73).

## R-15 공지사항

- **결정**: `board_type = 'NOTICE'`, `blog_id = NULL`인 글이다.
  - 메인 관리자(role = ADMIN)만 쓰고, 관리자면 누구나 수정·삭제한다(D-100 #19). 카테고리·태그·좋아요·댓글은 없다.
  - 화면은 `/notices`(목록), `/notices/{postId}`(상세), `/notices/write`(관리자)이다.
- **알림**: 공지를 올리면 `INSERT IGNORE INTO notifications ... SELECT`로 한 번에 넣는다.
  - 받는 사람: 관리자가 아닌 활동 회원 가운데 공지 알림 설정이 켜진 회원(설정 행이 없으면 켜짐)
  - `notification_type = NOTICE`, `tab = OPERATION`, `event_key = NOTICE:{postId}`
  - 회원이 많아져 느려지면 나눠 넣는 방식을 다시 본다. *가정*

## R-16 응답 시간과 5초 중단

- **서버**: 목록·검색·피드는 위 인덱스를 쓴다(`idx_posts_blog_id_status_created_at`, `idx_posts_status_created_at`, `idx_posts_status_like_count_created_at`, `idx_posts_title` FULLTEXT). `PostResponseTimeTest`가 글 5,000개로 2초 안을 확인한다(SC-001).
- **화면**: 공통 `api.js`에 `timeoutMs`(기본 5초, `AbortController`)를 둔다. 넘으면 "응답이 늦어 중단했어요. 다시 시도해 주세요" 안내와 다시 시도 버튼을 보여준다(FR-070, D-48).

## R-17 스키마 확인 결과

- 004가 쓰는 테이블과 인덱스는 Crowfoot 문서 654에서 배포한 스키마(`docs/04-design/schema.sql`)에 모두 있다.
  - 테이블: `categories`, `posts`, `tags`, `post_tags`, `images`, `comments`, `post_likes`, `recent_searches`, `post_views`, `notifications`, `notification_settings`, `user_blocks`, `follows`, `blog_subscriptions`
  - 인덱스: FULLTEXT `idx_posts_title`, 목록용 인덱스 3개, `idx_images_owner_type_owner_id`, `idx_comments_post_id_created_at`, `idx_recent_searches_user_id_searched_at`
- **DB 구조 변경 없음**. 카테고리를 지울 때 글을 미분류로 옮기는 것도 이미 있는 `fk_posts_categories ... ON DELETE SET NULL`로 된다.
- **Crowfoot 반영 (2026-10-08, 문서 654 v39)**:
  - 게시판 요구사항 REQ-040·041·044~051에 D-100 규칙을 넣고, 데이터로 확인하는 수용 기준 SQL을 붙였다. 예: 좋아요 수 = 좋아요 행 수, 대댓글 부모는 최상위, 공지에 댓글·좋아요 없음.
  - `categories`·`recent_searches`·`post_views` 설명과 `post_views.viewer_key` 설명의 "미정"을 고쳤다.
  - 반영 대기 요구사항은 0건이다.
  - 저장소의 `docs/04-design/schema.sql`도 같은 설명으로 맞췄다.
  - 연결된 DB 반영(`apply_migration`)은 사용자 승인 뒤에 한다. 계획에 예전부터 남은 삭제 문장 4건(users의 안 쓰는 칸 2개, CHECK 2개 다시 만들기)이 함께 나와서, 그것은 따로 승인받는다.
