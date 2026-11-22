import test from "node:test";
import assert from "node:assert/strict";
import { loadTs } from "./load-ts.mjs";

test("Google login always shows the account chooser so another account can sign in after logout", async () => {
  let options = null;
  class HttpError extends Error { constructor(status, message) { super(message); this.status = status; } }
  const route = loadTs("../app/api/auth/login/route.ts", {
    "next/headers": { cookies: async () => ({ set() {} }) },
    "@/server/kickx/config": { getSupabaseConfig: () => ({ url: "https://example.supabase.co", anonKey: "anon" }) },
    "@/server/kickx/supabase": { createRequestClient: async () => ({ auth: { signInWithOAuth: async (input) => { options = input; return { data: { url: "https://accounts.google.com/o/oauth2/auth" }, error: null }; } } }) },
    "@/server/kickx/http": { HttpError, requireOrigin() {}, readJson: async () => ({ next: "/squad" }), json: (body) => body, failure: (error) => { throw error; } },
    "@/lib/kickx/validation": { safeReturnPath: (value) => value },
  });
  const result = await route.POST(new Request("https://kick-x.example/api/auth/login", { method: "POST" }));
  assert.equal(result.url, "https://accounts.google.com/o/oauth2/auth");
  assert.equal(options.provider, "google");
  assert.equal(options.options.queryParams.prompt, "select_account");
  assert.equal(options.options.skipBrowserRedirect, true);
});
