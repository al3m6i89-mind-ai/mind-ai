-- Catalog for real phones on a Redroid node. Each version needs its image on the node
-- (the install script builds 12, 13 and 14 with Google Play; root images add Magisk).
INSERT INTO regions (id, display_name, country_code, provider_id, sort_order) VALUES
    ('node-main', 'Main server', NULL, 'redroid', 10);

INSERT INTO android_images (id, provider_id, android_version, api_level, display_name, device_type, root_supported, preinstalled_apps, sort_order) VALUES
    ('redroid-12', 'redroid', '12', 31, 'Android 12', 'VIRTUAL', TRUE,
        '["Google Play Store", "Google Play Services", "Settings", "Files", "Contacts", "Keyboard"]'::jsonb, 20),
    ('redroid-13', 'redroid', '13', 33, 'Android 13', 'VIRTUAL', TRUE,
        '["Google Play Store", "Google Play Services", "Settings", "Files", "Contacts", "Keyboard"]'::jsonb, 30),
    ('redroid-14', 'redroid', '14', 34, 'Android 14', 'VIRTUAL', TRUE,
        '["Google Play Store", "Google Play Services", "Settings", "Files", "Contacts", "Keyboard"]'::jsonb, 40);
