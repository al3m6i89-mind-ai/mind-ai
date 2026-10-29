-- Phone servers report their public address here, so a server behind a changing tunnel
-- (a home laptop, for example) needs no manual URL updates.
CREATE TABLE phone_nodes (
    id           VARCHAR(40)  PRIMARY KEY,
    public_url   VARCHAR(300) NOT NULL,
    last_seen_at TIMESTAMPTZ  NOT NULL
);
