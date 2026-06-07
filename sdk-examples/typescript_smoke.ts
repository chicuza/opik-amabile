/**
 * Opik TS SDK smoke test.
 *
 * Requires env vars:
 *   OPIK_URL_OVERRIDE, OPIK_API_KEY, OPIK_WORKSPACE
 *
 * Run:
 *   npm i opik
 *   npx tsx sdk-examples/typescript_smoke.ts
 */
import { Opik } from "opik";

async function main() {
  const apiKey = process.env.OPIK_API_KEY;
  const apiUrl = process.env.OPIK_URL_OVERRIDE;
  const workspaceName = process.env.OPIK_WORKSPACE ?? "default";

  if (!apiKey || !apiUrl) {
    console.error("missing OPIK_API_KEY or OPIK_URL_OVERRIDE");
    process.exit(1);
  }

  const client = new Opik({ apiKey, apiUrl, workspaceName, projectName: "amabile-smoke" });

  const trace = client.trace({
    name: "hello-ts",
    input: { q: "ping" },
    output: { a: "pong" },
    tags: ["smoke", "railway", "ts"],
  });
  await trace.end();
  await client.flush();
  console.log(`trace ok: ${trace.data.id}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
