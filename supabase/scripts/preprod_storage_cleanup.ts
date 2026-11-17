// Pre-production: delete Storage files tied to demo/test data. DRY RUN by default.
//
// 1. Produce the path list (read-only):
//      supabase db query --remote --read-only -f supabase/scripts/preprod_storage_paths.sql \
//        --output-format json > supabase/scripts/.preprod_paths.json
// 2. Dry run (prints what would be removed, deletes nothing):
//      deno run --allow-env --allow-net --allow-read supabase/scripts/preprod_storage_cleanup.ts supabase/scripts/.preprod_paths.json
// 3. Apply:
//      ... preprod_storage_cleanup.ts supabase/scripts/.preprod_paths.json --apply
//
// Needs env vars SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (export them in your shell only — never commit
// them, never put the service role key in the app). Only the exact paths in the JSON file are touched.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const ALLOWED_BUCKETS = new Set(["venue-submission-media", "review-media", "avatars"]);
// Avatars: "<uuid>.<ext>"; media: "<parent>/<uuid>.<ext>"; legacy media: "<user>/<parent>/<uuid>.<ext>".
const SAFE_PATH = /^([0-9a-f-]{36}\/){0,2}[0-9a-f-]{36}\.(jpg|jpeg|png|heic|webp)$/;

const [file, ...flags] = Deno.args;
const apply = flags.includes("--apply");
if (!file) {
  console.error("Usage: preprod_storage_cleanup.ts <paths.json> [--apply]");
  Deno.exit(2);
}

// Accepts the `supabase db query --output-format json` envelope ({ rows: [...] }) or a plain array.
const parsed = JSON.parse(await Deno.readTextFile(file));
const rows: { bucket: string; name: string }[] = Array.isArray(parsed) ? parsed : (parsed.rows ?? parsed.data ?? []);

const byBucket = new Map<string, string[]>();
for (const row of rows) {
  if (!ALLOWED_BUCKETS.has(row.bucket)) {
    console.error(`Refusing unknown bucket: ${row.bucket}`);
    Deno.exit(1);
  }
  if (!SAFE_PATH.test(row.name)) {
    console.error(`Refusing unexpected path shape: ${row.bucket}/${row.name}`);
    Deno.exit(1);
  }
  byBucket.set(row.bucket, [...(byBucket.get(row.bucket) ?? []), row.name]);
}

let total = 0;
for (const [bucket, names] of byBucket) {
  console.log(`${bucket}: ${names.length} file(s)`);
  for (const name of names) console.log(`  ${apply ? "DELETE" : "would delete"} ${bucket}/${name}`);
  total += names.length;
}
if (total === 0) {
  console.log("Nothing to delete.");
  Deno.exit(0);
}
if (!apply) {
  console.log(`\nDRY RUN: ${total} file(s) would be deleted. Re-run with --apply to delete them.`);
  Deno.exit(0);
}

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !key) {
  console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in your shell first.");
  Deno.exit(1);
}
const admin = createClient(url, key, { auth: { persistSession: false } });

let failed = 0;
for (const [bucket, names] of byBucket) {
  for (let i = 0; i < names.length; i += 100) {
    const batch = names.slice(i, i + 100);
    const { data, error } = await admin.storage.from(bucket).remove(batch);
    if (error) {
      failed += batch.length;
      console.error(`${bucket}: batch failed: ${error.message}`);
    } else {
      console.log(`${bucket}: removed ${data?.length ?? 0}/${batch.length}`);
    }
  }
}
Deno.exit(failed > 0 ? 1 : 0);
