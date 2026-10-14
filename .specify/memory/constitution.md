# 메인블로그 Constitution

메인블로그(티스토리형 블로그 플랫폼)의 모든 명세(spec), 계획(plan), 작업(tasks), 코드가 지켜야 하는 원칙입니다.
근거는 `docs/01-requirements/`(요구사항분석서 1), `docs/02-policies/`(6장 세부 정책), `docs/03-decisions/`(8장 결정 기록)입니다.

## Core Principles

### I. 보안 우선 (NON-NEGOTIABLE)

보안은 기능이 아니라 모든 기능에 걸리는 규칙입니다(4장).
- 비밀번호는 bcrypt 해시로만 저장한다(SEC-01, D-81).
- 로그인은 JWT + HttpOnly 쿠키, localStorage 금지. Refresh Token은 DB에 저장하고 로그아웃·비밀번호 변경 때 폐기한다(SEC-04, D-53, D-82).
- 상태를 바꾸는 요청은 CSRF 토큰을 검사하고, JS 요청은 `X-XSRF-TOKEN` 헤더를 붙인다(SEC-10).
- 글 본문은 서버에서 마크다운→HTML 변환 후 jsoup으로 걸러 보내고, 화면은 본문만 innerHTML, 나머지는 textContent로 넣는다(SEC-06, D-64).
- 보안 헤더(X-Frame-Options, nosniff, CSP, HSTS, Referrer-Policy)를 설정한다(SEC-12).
- 업로드는 확장자·MIME·파일 시그니처를 모두 검사하고 UUID 이름으로 저장하며 EXIF를 제거한다(SEC-08, 6.3).
- 가입·비밀번호 찾기 화면은 가입 여부를 드러내지 않는다(USR-02, USR-06, D-28).

### II. 블로그별 역할을 매 요청마다 서버에서 확인 (NON-NEGOTIABLE)

이 플랫폼에서 가장 중요한 규칙입니다(SEC-07). 블로그장·부블로그장·멤버는 계정 종류가 아니라 블로그별 역할입니다.
- 모든 요청에서 서버가 그 블로그에서의 역할을 DB로 확인한다. 토큰 내용만 믿지 않는다. 토큰에는 회원 번호 정도만 담는다.
- 주소 단위로 비회원·회원·관리자를 나누고, 블로그별 역할은 `@PreAuthorize` 메서드 보안으로 확인한다(SEC-11).
- A 블로그의 블로그장은 B 블로그를 관리할 수 없다. 누구도 다른 사람의 글을 수정할 수 없다(D-07, D-58).

### III. 개인정보는 서버에서 가리고, 필요한 만큼만 받는다

- 보는 사람에 따라 서버가 응답을 만들 때 가린다. 화면에서만 가리지 않는다(4.4, D-22).
- 메인 관리자의 "전체 보기"는 기록을 남긴다(ADM-06).
- 삭제·탈퇴·폐쇄 데이터는 30일 보관 후 완전 삭제한다. 예외(인증번호 즉시 삭제, 블랙리스트 해시 보관, 운영 기록 1년)는 4.5를 따른다(D-40, D-60).

### IV. 서버 이중화 대비: 서버에 상태를 두지 않는다

1차는 서버 1대지만, 서버를 늘릴 때 코드를 거의 고치지 않도록 지금부터 지킨다(4.3).
- 인증 코드, Refresh Token, 로그인 실패 횟수, 임시 데이터는 DB에 저장한다. IP별 요청 제한만 1차에 메모리(SCL-01).
- 파일 저장은 `FileStorage` 인터페이스로 분리한다(SCL-02, D-75).
- `@Scheduled` 작업에는 처음부터 ShedLock을 건다(SCL-03).
- 제한값은 하드코딩하지 않고 설정 파일 + 환경변수로 둔다. 예: `blog.limit.public=${BLOG_LIMIT_PUBLIC:3}`(D-68).

### V. 명세와 결정이 코드보다 먼저

- 기능은 `specs/` 명세에 있는 요구사항 ID(USR, BLG, SOC, BRD, ADM, SEC, SCL)를 근거로 만든다. 명세에 없는 동작은 만들지 않는다.
- 숫자와 규칙은 `docs/02-policies/`의 확정 값을 그대로 쓴다. 보류 항목은 임의로 정하지 않고 `[NEEDS CLARIFICATION]`으로 남긴다.
- 결정을 바꾸면 `docs/03-decisions/`에 새 D-번호를 추가하고, 이전 결정의 상태를 `변경됨 → D-xx`로 고친 뒤 명세를 갱신한다.

### VI. 단순하게 시작

- 1차 범위에서 확정된 방식만 쓴다: 알림은 30초 폴링(D-72), 메인 피드는 볼 때마다 모아오기(D-73), 이미지는 서버 디스크(D-75), 썸네일은 CSS 축소(6.3).
- 더 복잡한 방식(SSE, Redis, 피드 테이블, S3)은 성능 목표(4.2)를 넘기거나 이중화할 때 다시 검토한다.

## 기술 제약

- 백엔드: Spring Boot, Spring Security(D-09), MySQL
- 화면: 정적 HTML + JS(API 호출). 글 상세만 서버가 og 태그를 채운다(D-66)
- 에디터: Toast UI Editor, 마크다운 저장(D-74)
- 메일: Gmail SMTP, 6자리 인증번호를 Spring에서 직접 발송·검증(D-10, D-69)
- 사람 확인: Cloudflare Turnstile, 로그인 3회 실패 후 표시(SEC-13, D-79)
- 블로그 주소: 경로 방식 `/blog/{주소}`(D-70)
- 성능: 메인·목록·검색 1~2초 안에 응답(목표 1초), 5초 넘으면 중단하고 안내(4.2, D-48)
- 사용성: PC·모바일 반응형. 개별 블로그에서도 메인 상단 메뉴와 로그인 상태가 같게 보인다(4.2)

## 개발 흐름

1. `/speckit.specify` 또는 `specs/<번호>-<기능>/spec.md` 수정으로 명세를 확정한다.
2. `/speckit.clarify`로 `[NEEDS CLARIFICATION]` 항목을 사용자와 정한다.
3. `/speckit.plan`으로 plan.md, data-model.md, contracts/를 만든다. 계획은 이 Constitution Check를 통과해야 한다.
4. `/speckit.tasks`로 tasks.md를 만들고 그 순서대로 구현한다.
5. 커밋·PR에 관련 요구사항 ID와 결정 번호를 적는다. 예: `BLG-09, D-12`.

## Governance

- 이 문서는 다른 모든 관행보다 우선한다. 위반이 필요하면 plan.md의 Complexity Tracking에 이유를 적고 사용자 승인을 받는다.
- 원칙을 바꾸면 `docs/03-decisions/`에 결정을 남기고 아래 버전을 올린다(원칙 삭제·변경은 MAJOR, 추가는 MINOR, 문구 수정은 PATCH).
- 에이전트의 작업 규칙은 저장소 루트의 `CLAUDE.md`를 따른다.

**Version**: 1.0.0 | **Ratified**: 2026-10-07 | **Last Amended**: 2026-10-07
