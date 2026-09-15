// Intentionally never runs during application build/deployment.
// Use the connected SQL integration with this template, or psql after substituting
// runtime-supplied credentials. This helper produces SQL through a protected file.
import fs from "node:fs";
if (!["development", "testing"].includes(process.env.APP_ENV))
  throw new Error("Demo seed requires APP_ENV=development or testing");
const users = JSON.parse(
  fs.readFileSync(
    process.env.DEMO_CREDENTIAL_FILE || ".env.demo-test.json",
    "utf8",
  ),
);
let sql = fs.readFileSync("supabase/seeds/nova_demo.sql", "utf8");
for (const [name, user] of Object.entries(users))
  sql = sql.replaceAll(
    "__PASSWORD_" + name + "__",
    user.password.replaceAll("'", "''"),
  );
fs.writeFileSync(".env.demo-seed.sql", sql, { mode: 0o600 });
console.log(
  "Prepared protected demo seed file. Apply only to the selected non-production project.",
);
