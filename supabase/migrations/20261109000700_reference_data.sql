-- Nanglen v2 — 0007: reference data required in every environment (controlled tag taxonomy).
-- Tags are community-reported impressions, never verified venue facts.
insert into public.review_tags (slug, label_th, label_en, tag_group, sort_order) values
    ('study_friendly',      'เหมาะกับอ่านหนังสือ', 'Study-friendly',      'activity',    10),
    ('work_friendly',       'เหมาะกับทำงาน',      'Work-friendly',       'activity',    20),
    ('quiet',               'เงียบสงบ',           'Quiet',               'environment', 30),
    ('lively',              'บรรยากาศคึกคัก',      'Lively atmosphere',   'environment', 40),
    ('good_lighting',       'แสงดี',              'Good lighting',       'environment', 50),
    ('good_wifi',           'Wi-Fi ดี',           'Good Wi-Fi',          'amenity',     60),
    ('power_outlets',       'มีปลั๊กไฟ',           'Power outlets',       'amenity',     70),
    ('comfortable_seating', 'ที่นั่งสบาย',          'Comfortable seating', 'amenity',     80),
    ('good_value',          'คุ้มค่า',             'Good value',          'value',       90),
    ('expensive',           'ราคาค่อนข้างสูง',      'Expensive',           'value',      100)
on conflict (slug) do update set label_th = excluded.label_th, label_en = excluded.label_en,
    tag_group = excluded.tag_group, sort_order = excluded.sort_order;
