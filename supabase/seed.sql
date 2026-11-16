-- DEVELOPMENT / DEMO SEED ONLY — never run against production.
-- Fictional venues (marked "(Demo)") with name/category/location/address only; no invented amenities.
-- The same records are mirrored by the iOS DemoBackend (DemoSeed.swift).
insert into public.venues (id, name, category, formatted_address, location, provenance, description) values
    ('00000000-0000-4000-8000-000000000001', 'Baicha Café (Demo)',            'cafe',        'Siam Square Soi 3, Pathum Wan, Bangkok',        extensions.st_setsrid(extensions.st_makepoint(100.5326, 13.7462), 4326)::extensions.geography, 'curated_import', 'Sample coffee shop for testing'),
    ('00000000-0000-4000-8000-000000000002', 'Pathum Wan Community Library (Demo)',   'library',     'Rama I Road, Pathum Wan, Bangkok',            extensions.st_setsrid(extensions.st_makepoint(100.5300, 13.7440), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000003', 'Hive Corner Co-working (Demo)', 'coworking',   'Rama I Road, Pathum Wan, Bangkok',            extensions.st_setsrid(extensions.st_makepoint(100.5350, 13.7468), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000004', 'Samyan Reading Corner (Demo)',   'study_space', 'Samyan, Pathum Wan, Bangkok',                extensions.st_setsrid(extensions.st_makepoint(100.5290, 13.7330), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000005', 'Morning Drip Café (Demo)',      'cafe',        'Phloen Chit Road, Pathum Wan, Bangkok',            extensions.st_setsrid(extensions.st_makepoint(100.5390, 13.7440), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000006', 'Studio 24 Workspace (Demo)',    'coworking',   'Sukhumvit 21, Watthana, Bangkok',               extensions.st_setsrid(extensions.st_makepoint(100.5603, 13.7378), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000007', 'Parkside Lounge (Demo)',       'other',       'Ratchadamri Road, Pathum Wan, Bangkok',             extensions.st_setsrid(extensions.st_makepoint(100.5415, 13.7305), 4326)::extensions.geography, 'curated_import', null),
    ('00000000-0000-4000-8000-000000000008', 'Paper & Bean (Demo)',           'cafe',        'Banthat Thong, Pathum Wan, Bangkok',              extensions.st_setsrid(extensions.st_makepoint(100.5235, 13.7420), 4326)::extensions.geography, 'curated_import', null)
on conflict (id) do nothing;

insert into public.venue_provider_refs (venue_id, provider, external_place_id)
select id, 'curated', 'seed:' || id::text from public.venues where provenance = 'curated_import'
on conflict (provider, external_place_id) do nothing;
