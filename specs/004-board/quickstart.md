# 004 게시판 확인 안내 (Quickstart)

**명세**: [spec.md](spec.md) | **API**: [contracts/board-api.yaml](contracts/board-api.yaml) | **데이터**: [data-model.md](data-model.md)

## 준비

- 자동 테스트: Docker가 돌고 있으면 `./gradlew test`(Testcontainers MySQL 8)로 전부 확인한다.
- 화면 확인: `local/start.sh`(Windows는 `local\start.bat`)로 MySQL·Mailpit·앱을 띄우고 http://localhost:8080 을 연다. 시드 계정은 모두 비밀번호 `Passw0rd!`이다.
  - `owner@local.test`: travel-log 블로그장
  - `member@local.test`: travel-log 멤버
  - `newbie@local.test`: 멤버 아님
  - `admin@local.test`: 메인 관리자

## 시나리오별 확인

| # | 확인할 것 | 방법 | 기대 결과 | 근거 |
|---|---|---|---|---|
| 1 | 글쓰기·읽기 | member로 /blog/travel-log → 글쓰기, 제목·본문(이미지 1장) 저장 | 상세에 본문·이미지·닉네임, 목록 맨 위 | US1, FR-002 |
| 2 | 글자 수 | 제목 31자, 본문 5,001자를 API로 직접 보냄 | 400 VALIDATION_FAILED | FR-003, D-92 |
| 3 | XSS | 본문 `<script>alert(1)</script><img src=x onerror=alert(1)>`, 제목 `<b>굵게</b>` | 스크립트 실행 없음, 제목은 글자 그대로 | SC-002 |
| 4 | 수정·삭제 권한 | owner로 member 글 수정 시도 → 삭제 | 수정 403, 삭제 성공 + member에게 "내 글 삭제됨" 알림 | SC-004, FR-011 |
| 5 | 관리자 글쓰기 | admin으로 블로그 글쓰기 API | 403 ADMIN_NOT_ALLOWED, 공지는 성공 | D-90 |
| 6 | 목록·페이지 | 글 35개(테스트 데이터)로 size 10·20·30, 50 | 4·2·2페이지, 50은 400 | US2 |
| 7 | 카테고리 | owner가 "여행" 추가, 글 분류, 카테고리 삭제 | 필터 동작, 삭제 후 글은 미분류 | D-100 #8 |
| 8 | 태그 | `#맛집`, ` 서울 `, `Java`, `제주 여행`, `java` | 맛집·서울·java·제주_여행, 중복 하나 | SC-009 |
| 9 | 이미지 검사 | 3MB 초과, 확장자만 바꾼 exe, svg, 11장째, GPS 사진 | 모두 막힘, 저장 파일에 EXIF 없음 | SC-003 |
| 10 | 댓글 | 댓글 → 답글 → 답글에 답글 → 부모 삭제 → 답글 모두 삭제 | 같은 단계 + @닉네임, "삭제된 댓글입니다" → 사라짐 | D-100 #3·#10 |
| 11 | 좋아요 | 동시 10번 요청, 취소 후 다시 누름 | 좋아요 1개, 알림 1건 | SC-006, D-100 #13 |
| 12 | 조회수 | 같은 회원 20번 새로고침, 다음 날(Clock), 작성자 본인, UA `Googlebot` | 1, 2, 그대로, 그대로 | SC-005, D-100 #20·#21 |
| 13 | 검색 | "여행"으로 ALL·TAG·NICKNAME, 비공개·일부 공개 블로그 섞기 | 공개만, 결과 수에도 빠짐 | SC-007, D-100 #16 |
| 14 | 최근 검색어 | 11개 검색, 같은 말 다시 검색, x, 전체 삭제 | 10개, 맨 앞으로, 지워짐 | D-100 #17 |
| 15 | 피드 | 최신·인기(좋아요 8·3·3), 구독 탭 20개씩 더 보기 | P, R, Q 순서, 더 보기 동작 | US3, D-100 #18 |
| 16 | 미리보기 | `curl -s http://localhost:8080/blog/travel-log/posts/{id} \| grep og:` | og:title "제목 - 닉네임", og:description 100자, og:image 첫 이미지 | SC-010 |
| 17 | 일부 공개 미리보기 | LINK 블로그 글을 share 값 없이/있이 curl | 없으면 사이트 기본, 있으면 글 미리보기 | D-100 #6 |
| 18 | 공지 | admin이 공지 작성, notice 알림 끈 회원 비교 | 켠 회원만 알림 | US10 |
| 19 | 30일 정리 | 글 삭제 → Clock 31일 뒤 04:00 작업 | 글·댓글 행 없음, 이미지 deleted_at | SC-012 |
| 20 | 개인정보 | 글·댓글·검색·피드 응답 전체에서 이메일·전화번호 찾기 | 0건 | SC-011 |
| 21 | 화면 | 360px 폭에서 글쓰기·상세·목록·검색·피드 | 가로 스크롤 없음, 상단 메뉴 같음 | SC-013 |

## 확인 결과

2026-10-08 개발 환경에서 확인함.

- 자동 테스트: `./gradlew test` 전체 통과(440개 + 보안·성능·시드 테스트). 시나리오 1~20은 `board/*IntegrationTest`, `BoardSecurityTest`, `perf/PostResponseTimeTest`가 같은 조건으로 확인한다.
- 화면(21): Toast UI 에디터를 앱과 같은 CSP로 360px·1280px에서 열어 입력·마크다운 저장·가로 스크롤 없음을 확인했다. 인라인 스타일이 막혀 툴바 팝업이 깨져서 `style-src 'self' 'unsafe-inline'`을 더했다(D-101).
- 아직 못 한 것: Crowfoot DB에 붙인 실제 앱으로 글 상세·검색·피드 화면을 눌러 보는 확인. 게시판 시드(`local/seed.sql` 아래쪽)를 Crowfoot DB에 넣으면 사용자 컴퓨터에서 바로 볼 수 있다.
