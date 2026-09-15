import fs from "node:fs";
import { randomBytes } from "node:crypto";
if (!["development", "testing"].includes(process.env.APP_ENV))
  throw new Error("Choose APP_ENV=development or testing");
if (!process.env.DEMO_PASSWORD || process.env.DEMO_PASSWORD.length < 8)
  throw new Error(
    "Set DEMO_PASSWORD to the desired owner password (at least 8 characters)",
  );
const filename = process.env.DEMO_CREDENTIAL_FILE || ".env.demo-test.json";
if (fs.existsSync(filename))
  throw new Error(
    "Credential file already exists; preserve it or choose another filename",
  );
const users = {
  owner: {
    email: "admin@nova.example.test",
    id: "c94a7c99-7833-51da-aa7c-1edd2592ce71",
  },
  manager: {
    email: "manager@nova.example.test",
    id: "1b833245-6ef7-5fab-b096-78605cbde7f1",
  },
  operator: {
    email: "operator@nova.example.test",
    id: "90a63464-4abd-5143-b2c2-062fd16efb53",
  },
  support: {
    email: "support@nova.example.test",
    id: "3f9d81aa-562a-54c0-bd6d-d48b85d9bdbe",
  },
};
for (const [role, user] of Object.entries(users))
  user.password =
    role === "owner"
      ? process.env.DEMO_PASSWORD
      : randomBytes(20).toString("base64url");
fs.writeFileSync(filename, JSON.stringify(users, null, 2), { mode: 0o600 });
console.log("Created a protected credential file. No passwords were printed.");
