-- Starter catalog. Prices are placeholders until real infrastructure costs are known
-- and are editable from the admin dashboard (phase 3). Images point at the dev-only
-- "mock" provider; real images are added when a real provider is installed.

INSERT INTO regions (id, display_name, country_code, sort_order) VALUES
    ('dev-local', 'Development (simulated)', NULL, 0);

INSERT INTO android_images (id, provider_id, android_version, api_level, display_name, device_type, root_supported, preinstalled_apps, sort_order) VALUES
    ('mock-android-10', 'mock', '10', 29, 'Android 10', 'VIRTUAL', TRUE,
        '["Browser", "Files", "Settings", "Keyboard", "F-Droid"]'::jsonb, 10),
    ('mock-android-12', 'mock', '12', 31, 'Android 12', 'VIRTUAL', TRUE,
        '["Browser", "Files", "Settings", "Keyboard", "F-Droid"]'::jsonb, 20),
    ('mock-android-13', 'mock', '13', 33, 'Android 13', 'VIRTUAL', TRUE,
        '["Browser", "Files", "Settings", "Keyboard", "F-Droid"]'::jsonb, 30);

INSERT INTO plans (id, code, name, billing_period, price, currency, device_type, device_limit, concurrent_session_limit,
                   cpu_cores, ram_mb, storage_gb, screen_width, screen_height, screen_dpi, max_fps,
                   always_on, root_allowed, data_retention_days, sort_order) VALUES
    ('7b0c4e7e-0f1d-4a53-9f0b-3d1f6f6b0001', 'starter-day', 'Starter · 1 day', 'DAY', 0.99, 'USD', 'VIRTUAL', 1, 1,
        2, 3072, 16, 720, 1280, 320, 30, FALSE, TRUE, 3, 10),
    ('7b0c4e7e-0f1d-4a53-9f0b-3d1f6f6b0002', 'standard-month', 'Standard · monthly', 'MONTH', 9.99, 'USD', 'VIRTUAL', 2, 1,
        4, 4096, 32, 1080, 1920, 420, 30, TRUE, TRUE, 14, 20),
    ('7b0c4e7e-0f1d-4a53-9f0b-3d1f6f6b0003', 'pro-month', 'Pro · monthly', 'MONTH', 24.99, 'USD', 'VIRTUAL', 5, 3,
        4, 8192, 64, 1080, 2340, 440, 60, TRUE, TRUE, 30, 30);
