-- DEVELOPMENT / DEMO SEED ONLY — never run against production.
-- Fictional venues (marked "(ตัวอย่าง)") with name/category/location/address only; no invented amenities.
-- The same records are mirrored by the iOS DemoBackend (DemoSeed.swift).
insert into public.venues (id, name, category, formatted_address, location, provenance, description) values
    ('00000000-0000-4000-8000-000000000001', 'ใบชา คาเฟ่ (ตัวอย่าง)',            'cafe',        'สยามสแควร์ ซอย 3 ปทุมวัน กรุงเทพฯ',        extensions.st_setsrid(extensions.st_makepoint(100.5326, 13.7462), 4326)::extensions.geography, 'curated_import', 'ร้านกาแฟตัวอย่างสำหรับทดสอบระบบ'),
    ('00000000-0000-4000-8000-000000000002', 'ห้องสมุดชุมชนปทุมวัน (ตัวอย่าง)',   'library',     'ถนนพระราม 1 ปทุมวัน กรุงเทพฯ',            extensions.st_setsrid(extensions.st_makepoint(100.5300, 13.7440), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000003', 'Hive Corner Co-working (ตัวอย่าง)', 'coworking',   'ถนนพระราม 1 ปทุมวัน กรุงเทพฯ',            extensions.st_setsrid(extensions.st_makepoint(100.5350, 13.7468), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000004', 'มุมอ่านหนังสือสามย่าน (ตัวอย่าง)',   'study_space', 'สามย่าน ปทุมวัน กรุงเทพฯ',                extensions.st_setsrid(extensions.st_makepoint(100.5290, 13.7330), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000005', 'Morning Drip Café (ตัวอย่าง)',      'cafe',        'ถนนเพลินจิต ปทุมวัน กรุงเทพฯ',            extensions.st_setsrid(extensions.st_makepoint(100.5390, 13.7440), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000006', 'Studio 24 Workspace (ตัวอย่าง)',    'coworking',   'สุขุมวิท 21 วัฒนา กรุงเทพฯ',               extensions.st_setsrid(extensions.st_makepoint(100.5603, 13.7378), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000007', 'ลานนั่งเล่นริมสวน (ตัวอย่าง)',       'other',       'ถนนราชดำริ ปทุมวัน กรุงเทพฯ',             extensions.st_setsrid(extensions.st_makepoint(100.5415, 13.7305), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000008', 'Paper & Bean (ตัวอย่าง)',           'cafe',        'บรรทัดทอง ปทุมวัน กรุงเทพฯ',              extensions.st_setsrid(extensions.st_makepoint(100.5235, 13.7420), 4326)::extensions.geography, 'curated_import', null)
on conflict (id) do nothing;

insert into public.venue_provider_refs (venue_id, provider, external_place_id)
select id, 'curated', 'seed:' || id::text from public.venues where provenance = 'curated_import'
on conflict (provider, external_place_id) do nothing;
