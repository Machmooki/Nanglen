// Deletes the CALLER's account and uploaded photos (App Store guideline 5.1.1(v), PDPA data deletion).
// Runs with the service role inside Supabase; the key never reaches the app.
// Deploy: supabase functions deploy delete-account
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const cors = { "Content-Type": "application/json" };

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405, headers: cors });
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Identify the caller from THEIR JWT. Never accept a user id from the request body.
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return new Response(JSON.stringify({ error: "not_authenticated" }), { status: 401, headers: cors });
  }
  const uid = userData.user.id;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // Admin accounts keep their audit trail; revoke admin first, then delete.
  const { data: blocked, error: checkError } = await admin.rpc("account_deletion_blocked", { p_user: uid });
  if (checkError) {
    return new Response(JSON.stringify({ error: "check_failed" }), { status: 500, headers: cors });
  }
  if (blocked) {
    return new Response(JSON.stringify({ error: "admin_account" }), { status: 409, headers: cors });
  }

  // Remove Storage objects first (DB cascades do not delete files).
  const [subMedia, revMedia, profile] = await Promise.all([
    admin.from("venue_submission_media").select("storage_path, status").eq("uploaded_by", uid),
    admin.from("review_media").select("storage_path").eq("uploaded_by", uid),
    admin.from("profiles").select("avatar_path").eq("id", uid).maybeSingle(),
  ]);
  // Photos already published on an approved venue stay (they belong to the venue listing).
  const submissionPaths = (subMedia.data ?? []).filter((m) => m.status !== "approved").map((m) => m.storage_path);
  const reviewPaths = (revMedia.data ?? []).map((m) => m.storage_path);
  if (submissionPaths.length) await admin.storage.from("venue-submission-media").remove(submissionPaths);
  if (reviewPaths.length) await admin.storage.from("review-media").remove(reviewPaths);
  // Profile photo (current one; older ones were deleted by the app when replaced).
  const avatarPath = profile.data?.avatar_path as string | null | undefined;
  if (avatarPath) await admin.storage.from("avatars").remove([avatarPath]);

  // Cascades: profile, favorites, reviews + revisions, submissions, claims, memberships, verifications.
  const { error } = await admin.auth.admin.deleteUser(uid);
  if (error) {
    return new Response(JSON.stringify({ error: "delete_failed" }), { status: 500, headers: cors });
  }
  return new Response(JSON.stringify({ deleted: true }), { status: 200, headers: cors });
});
