# 04-design

DB(ERD)·API·아키텍처 설계 문서를 둡니다.

- DB 설계는 요구사항 정리가 끝난 뒤에 합니다(D-47).
- 파일 예: `erd.md`(전체 ERD), `architecture.md`. 기능별 data-model.md는 `specs/<번호>-<기능>/`에 만듭니다.
- 테스트가 직접 읽는 테이블 정의(`schema.sql`)와 API 계약(OpenAPI)은 소스 저장소의 `db/schema.sql`, `api-contracts/`에 있습니다. 개발환경 설명은 소스 저장소 `DEVELOPMENT.md`로 옮겼습니다(D-130).
- 설계마다 관련 요구사항 ID와 결정 번호를 적습니다.

## 문서

- [deployment-methods.md](deployment-methods.md): 도커 컨테이너와 예전 jar 직접 실행 비교(D-106, D-127, D-129)
