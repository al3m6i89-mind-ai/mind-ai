-- Core schema for Nuvola cloud phone service.

CREATE TABLE users (
    id                    UUID PRIMARY KEY,
    email                 VARCHAR(320) NOT NULL,
    password_hash         VARCHAR(100),
    display_name          VARCHAR(80)  NOT NULL,
    locale                VARCHAR(10)  NOT NULL DEFAULT 'ar',
    email_verified        BOOLEAN      NOT NULL DEFAULT FALSE,
    role                  VARCHAR(30)  NOT NULL DEFAULT 'USER'
        CHECK (role IN ('USER', 'SUPPORT_AGENT', 'BILLING_ADMIN', 'OPERATIONS_ADMIN', 'SUPER_ADMIN')),
    account_status        VARCHAR(30)  NOT NULL DEFAULT 'ACTIVE'
        CHECK (account_status IN ('ACTIVE', 'SUSPENDED', 'PENDING_DELETION', 'DELETED')),
    terms_version         VARCHAR(20)  NOT NULL,
    terms_accepted_at     TIMESTAMPTZ  NOT NULL,
    deletion_requested_at TIMESTAMPTZ,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_users_email ON users (lower(email));

CREATE TABLE email_tokens (
    id          UUID PRIMARY KEY,
    user_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    purpose     VARCHAR(30) NOT NULL CHECK (purpose IN ('VERIFY_EMAIL', 'RESET_PASSWORD')),
    token_hash  VARCHAR(64) NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_email_tokens_user ON email_tokens (user_id, purpose);

-- Login sessions (one per signed-in app install). Refresh tokens are stored hashed only.
CREATE TABLE user_sessions (
    id                 UUID PRIMARY KEY,
    user_id            UUID         NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(64)  NOT NULL UNIQUE,
    previous_token_hash VARCHAR(64),
    client_label       VARCHAR(120),
    ip_address         VARCHAR(64),
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_used_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ  NOT NULL,
    revoked_at         TIMESTAMPTZ,
    revoke_reason      VARCHAR(40)
);
CREATE INDEX ix_user_sessions_user ON user_sessions (user_id) WHERE revoked_at IS NULL;
CREATE INDEX ix_user_sessions_prev ON user_sessions (previous_token_hash);

CREATE TABLE regions (
    id           VARCHAR(40) PRIMARY KEY,
    display_name VARCHAR(80) NOT NULL,
    country_code VARCHAR(2),
    active       BOOLEAN     NOT NULL DEFAULT TRUE,
    sort_order   INT         NOT NULL DEFAULT 0
);

-- Android system images an operator has actually installed on a provider.
CREATE TABLE android_images (
    id             VARCHAR(40)  PRIMARY KEY,
    provider_id    VARCHAR(40)  NOT NULL,
    android_version VARCHAR(10) NOT NULL,
    api_level      INT          NOT NULL,
    display_name   VARCHAR(80)  NOT NULL,
    device_type    VARCHAR(20)  NOT NULL CHECK (device_type IN ('VIRTUAL', 'PHYSICAL')),
    root_supported BOOLEAN      NOT NULL DEFAULT FALSE,
    preinstalled_apps JSONB     NOT NULL DEFAULT '[]'::jsonb,
    active         BOOLEAN      NOT NULL DEFAULT TRUE,
    sort_order     INT          NOT NULL DEFAULT 0
);

CREATE TABLE plans (
    id                       UUID PRIMARY KEY,
    code                     VARCHAR(40)   NOT NULL UNIQUE,
    name                     VARCHAR(80)   NOT NULL,
    billing_period           VARCHAR(20)   NOT NULL CHECK (billing_period IN ('DAY', 'WEEK', 'MONTH', 'QUARTER', 'YEAR')),
    price                    NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    currency                 VARCHAR(3)       NOT NULL,
    device_type              VARCHAR(20)   NOT NULL CHECK (device_type IN ('VIRTUAL', 'PHYSICAL')),
    device_limit             INT           NOT NULL CHECK (device_limit > 0),
    concurrent_session_limit INT           NOT NULL CHECK (concurrent_session_limit > 0),
    cpu_cores                INT           NOT NULL,
    ram_mb                   INT           NOT NULL,
    storage_gb               INT           NOT NULL,
    screen_width             INT           NOT NULL,
    screen_height            INT           NOT NULL,
    screen_dpi               INT           NOT NULL,
    max_fps                  INT           NOT NULL,
    always_on                BOOLEAN       NOT NULL DEFAULT FALSE,
    root_allowed             BOOLEAN       NOT NULL DEFAULT FALSE,
    data_retention_days      INT           NOT NULL DEFAULT 7,
    feature_config           JSONB         NOT NULL DEFAULT '{}'::jsonb,
    active                   BOOLEAN       NOT NULL DEFAULT TRUE,
    sort_order               INT           NOT NULL DEFAULT 0,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE subscriptions (
    id                 UUID PRIMARY KEY,
    user_id            UUID        NOT NULL REFERENCES users (id),
    plan_id            UUID        NOT NULL REFERENCES plans (id),
    status             VARCHAR(30) NOT NULL CHECK (status IN ('PENDING_PAYMENT', 'ACTIVE', 'EXPIRED', 'CANCELED')),
    starts_at          TIMESTAMPTZ,
    expires_at         TIMESTAMPTZ,
    renewal_status     VARCHAR(20) NOT NULL DEFAULT 'OFF' CHECK (renewal_status IN ('AUTO', 'OFF')),
    provider           VARCHAR(40) NOT NULL,
    provider_reference VARCHAR(200),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_subscriptions_user ON subscriptions (user_id);
CREATE INDEX ix_subscriptions_expiry ON subscriptions (expires_at) WHERE status = 'ACTIVE';

CREATE TABLE cloud_devices (
    id                  UUID PRIMARY KEY,
    owner_user_id       UUID         NOT NULL REFERENCES users (id),
    subscription_id     UUID         NOT NULL REFERENCES subscriptions (id),
    provider_id         VARCHAR(40)  NOT NULL,
    provider_device_ref VARCHAR(200),
    device_type         VARCHAR(20)  NOT NULL CHECK (device_type IN ('VIRTUAL', 'PHYSICAL')),
    display_name        VARCHAR(60)  NOT NULL,
    android_image_id    VARCHAR(40)  NOT NULL REFERENCES android_images (id),
    android_version     VARCHAR(10)  NOT NULL,
    region              VARCHAR(40)  NOT NULL REFERENCES regions (id),
    cpu_config          INT          NOT NULL,
    ram_config          INT          NOT NULL,
    storage_config      INT          NOT NULL,
    screen_width        INT          NOT NULL,
    screen_height       INT          NOT NULL,
    screen_dpi          INT          NOT NULL,
    root_enabled        BOOLEAN      NOT NULL DEFAULT FALSE,
    lifecycle_status    VARCHAR(30)  NOT NULL CHECK (lifecycle_status IN
        ('CREATING', 'STARTING', 'RUNNING', 'STOPPING', 'STOPPED', 'RESTARTING', 'OFFLINE', 'ERROR', 'DELETING', 'DELETED')),
    status_detail       VARCHAR(300),
    idempotency_key     VARCHAR(80)  NOT NULL,
    last_seen_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,
    CONSTRAINT ux_devices_idempotency UNIQUE (owner_user_id, idempotency_key)
);
CREATE INDEX ix_devices_owner ON cloud_devices (owner_user_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_devices_subscription ON cloud_devices (subscription_id) WHERE deleted_at IS NULL;

CREATE TABLE device_jobs (
    id           UUID PRIMARY KEY,
    device_id    UUID        NOT NULL REFERENCES cloud_devices (id),
    type         VARCHAR(20) NOT NULL CHECK (type IN ('CREATE', 'START', 'STOP', 'RESTART', 'DESTROY', 'SET_ROOT')),
    status       VARCHAR(20) NOT NULL CHECK (status IN ('QUEUED', 'RUNNING', 'SUCCEEDED', 'FAILED')),
    payload      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    attempts     INT         NOT NULL DEFAULT 0,
    max_attempts INT         NOT NULL DEFAULT 3,
    run_after    TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at   TIMESTAMPTZ,
    finished_at  TIMESTAMPTZ,
    last_error   VARCHAR(500),
    requested_by UUID,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- At most one queued or running job per device, so double taps cannot race.
CREATE UNIQUE INDEX ux_device_jobs_active ON device_jobs (device_id) WHERE status IN ('QUEUED', 'RUNNING');
CREATE INDEX ix_device_jobs_pick ON device_jobs (run_after) WHERE status = 'QUEUED';

CREATE TABLE device_sessions (
    id                UUID PRIMARY KEY,
    user_id           UUID        NOT NULL REFERENCES users (id),
    cloud_device_id   UUID        NOT NULL REFERENCES cloud_devices (id),
    connection_status VARCHAR(20) NOT NULL CHECK (connection_status IN ('PENDING', 'CONNECTED', 'ENDED', 'EXPIRED')),
    token_hash        VARCHAR(64) NOT NULL UNIQUE,
    token_expires_at  TIMESTAMPTZ NOT NULL,
    token_used_at     TIMESTAMPTZ,
    started_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at          TIMESTAMPTZ,
    last_activity_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_device_sessions_open ON device_sessions (user_id) WHERE ended_at IS NULL;

CREATE TABLE payments (
    id                      UUID PRIMARY KEY,
    user_id                 UUID           NOT NULL REFERENCES users (id),
    subscription_id         UUID           REFERENCES subscriptions (id),
    provider                VARCHAR(40)    NOT NULL,
    provider_transaction_id VARCHAR(200),
    idempotency_key         VARCHAR(80)    NOT NULL,
    amount                  NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    currency                VARCHAR(3)        NOT NULL,
    status                  VARCHAR(20)    NOT NULL CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED', 'REFUNDED', 'CANCELED')),
    created_at              TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT ux_payments_idempotency UNIQUE (user_id, idempotency_key),
    CONSTRAINT ux_payments_provider_tx UNIQUE (provider, provider_transaction_id)
);

CREATE SEQUENCE invoice_number_seq START 1000;
CREATE TABLE invoices (
    id             UUID PRIMARY KEY,
    user_id        UUID           NOT NULL REFERENCES users (id),
    payment_id     UUID           NOT NULL UNIQUE REFERENCES payments (id),
    invoice_number VARCHAR(30)    NOT NULL UNIQUE,
    total          NUMERIC(12, 2) NOT NULL,
    tax            NUMERIC(12, 2) NOT NULL DEFAULT 0,
    currency       VARCHAR(3)        NOT NULL,
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT now()
);
CREATE INDEX ix_invoices_user ON invoices (user_id);

CREATE TABLE audit_logs (
    id          UUID PRIMARY KEY,
    actor_id    UUID,
    actor_type  VARCHAR(20)  NOT NULL CHECK (actor_type IN ('USER', 'ADMIN', 'SYSTEM')),
    action      VARCHAR(60)  NOT NULL,
    target_type VARCHAR(40)  NOT NULL,
    target_id   VARCHAR(80),
    metadata    JSONB        NOT NULL DEFAULT '{}'::jsonb,
    ip_address  VARCHAR(64),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX ix_audit_target ON audit_logs (target_type, target_id);
CREATE INDEX ix_audit_actor ON audit_logs (actor_id, created_at DESC);

CREATE SEQUENCE ticket_number_seq START 10000;
CREATE TABLE support_tickets (
    id            UUID PRIMARY KEY,
    ticket_number VARCHAR(20)  NOT NULL UNIQUE,
    user_id       UUID         NOT NULL REFERENCES users (id),
    category      VARCHAR(30)  NOT NULL CHECK (category IN ('DEVICE', 'CONNECTION', 'BILLING', 'ACCOUNT', 'OTHER')),
    subject       VARCHAR(150) NOT NULL,
    description   TEXT         NOT NULL,
    cloud_device_id UUID       REFERENCES cloud_devices (id),
    status        VARCHAR(20)  NOT NULL CHECK (status IN ('OPEN', 'WAITING_FOR_USER', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX ix_tickets_user ON support_tickets (user_id, created_at DESC);

CREATE TABLE support_messages (
    id          UUID PRIMARY KEY,
    ticket_id   UUID        NOT NULL REFERENCES support_tickets (id) ON DELETE CASCADE,
    author_type VARCHAR(10) NOT NULL CHECK (author_type IN ('USER', 'AGENT')),
    author_id   UUID        NOT NULL REFERENCES users (id),
    body        TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_support_messages_ticket ON support_messages (ticket_id, created_at);
