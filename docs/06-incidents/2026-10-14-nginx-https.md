# 2026-10-14 nginx 설정을 바꾼 뒤 https 인증서 경고

- 버전: v1.14
- 관련: D-129(롤링 배포)

#### 무슨 일이 있었나
- 롤링 배포용으로 서버 `~/nginx/mainttblog.java21.net.conf`를 저장소 사본(`deploy/nginx/`)으로 통째로 바꿨습니다.
- nginx가 새 파일을 읽은 뒤 브라우저에 "연결된 네트워크가 비공개가 아님"(인증서 경고)이 떴습니다.

#### 원인
- 저장소 사본에는 Certbot이 서버 파일에 넣은 줄이 없었습니다.
- 빠진 줄: `listen 443 ssl`, `ssl_certificate`, `ssl_certificate_key`, http → https 이동(301) 블록.
- 그래서 https를 받을 설정이 사라졌습니다.

#### 해결
1. 바꾸기 전에 남긴 `.bak` 파일로 되돌렸습니다.
2. 예전 파일에서 두 군데만 고쳤습니다: 맨 위에 `upstream`(8370·8371) 추가, `proxy_pass`를 upstream으로 바꾸고 `proxy_next_upstream` 2줄 추가.
3. `diff`로 https 줄이 그대로인지 확인했습니다.
4. 저장소 사본을 서버 파일 기준(https 포함)으로 고쳤습니다.

주의: 서버 nginx 파일은 저장소 사본으로 통째로 덮어쓰지 않습니다. 고칠 줄만 바꾸고, 바꾸기 전에 `.bak`을 남깁니다.
