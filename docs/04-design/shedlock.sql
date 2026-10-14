-- ShedLock 잠금 테이블 (research R-13, REQ-005).
-- 2026-10-08부터 Crowfoot ERD(REQ-060)와 schema.sql에도 들어 있다. 이 파일은 IF NOT EXISTS라 함께 넣어도 된다.
CREATE TABLE IF NOT EXISTS shedlock (
    name VARCHAR(64) NOT NULL,
    lock_until TIMESTAMP(3) NOT NULL,
    locked_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    locked_by VARCHAR(255) NOT NULL,
    PRIMARY KEY (name)
);
