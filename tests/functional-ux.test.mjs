import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { build } from "esbuild";
import en from "../src/locales/en.json" with { type: "json" };
import ar from "../src/locales/ar.json" with { type: "json" };

const require = createRequire(import.meta.url);
const bundled = await build({ entryPoints: ["src/features/CenterCapabilities.tsx"],
  bundle: true, platform: "node", format: "cjs", packages: "external",
  write: false, logLevel: "silent" });
const fakeReact = { useState: (initial) => [initial, () => {}] };
const module = { exports: {} };
new Function("require", "module", "exports", bundled.outputFiles[0].text)(
  (name) => name === "react" ? fakeReact : require(name), module, module.exports);
const CenterCapabilities = module.exports.default;

function firstForm(node) {
  if (!node || typeof node !== "object") return null;
  if (Array.isArray(node)) return node.map(firstForm).find(Boolean) || null;
  if (node.type === "form") return node;
  return firstForm(node.props?.children);
}

test("clearing an existing rate needs confirmation before changing capabilities", async () => {
  const originalFormData = globalThis.FormData;
  const originalConfirm = globalThis.confirm;
  let confirmed = false;
  let calls = 0;
  try {
    globalThis.FormData = class { get() { return ""; } };
    globalThis.confirm = (message) => { assert.equal(message, en.confirmRemoveCapabilities); return confirmed; };
    const snapshot = { factory: { id: "F" }, tables: {
      products: [{ id: "P", name: "Pipe" }],
      work_center_capabilities: [{ work_center_id: "C", product_id: "P", rate: 20 }],
    } };
    const tree = CenterCapabilities({ centerId: "C", snapshot, lang: "en",
      t: (key) => en[key] || key, can: () => true,
      command: async (name, args) => {
        calls++;
        assert.equal(name, "configure_center_capabilities");
        assert.deepEqual(args.capabilities, []);
      } });
    const form = firstForm(tree);
    assert.ok(form);
    await form.props.onSubmit({ preventDefault() {}, currentTarget: {} });
    assert.equal(calls, 0);
    confirmed = true;
    await form.props.onSubmit({ preventDefault() {}, currentTarget: {} });
    assert.equal(calls, 1);
  } finally {
    globalThis.FormData = originalFormData;
    globalThis.confirm = originalConfirm;
  }
});

test("active Planning and navigation prompts have matching English and Arabic labels", () => {
  for (const dictionary of [en, ar]) {
    for (const key of ["chooseLine", "backToOverview", "confirmRemoveCapabilities"])
      assert.ok(dictionary[key] && dictionary[key] !== key, key);
    assert.ok(dictionary.downtimeCaptureHelp.toLocaleLowerCase().includes(
      dictionary.floor.toLocaleLowerCase()));
    assert.ok(dictionary.downtimeCaptureHelp.includes(dictionary.stopMachine));
  }
});
