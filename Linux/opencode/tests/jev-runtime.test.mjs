import test from "node:test";
import assert from "node:assert/strict";
import { resolveTypeSafe, readSessionView, readCatalogs, unwrap } from "../jev/runtime.mjs";

test("credential rotation changes opaque cache identity without exposing keys", async () => {
  let connection = { type: "credential", id: "one", method: "key" };
  let value = { type: "key", key: "secret-one" };
  const ctx = { integration: { connection: {
    active: async id => { assert.equal(id, "typesafe"); return connection; },
    resolve: async selected => { assert.equal(selected, connection); return value; },
  } } };
  const first = await resolveTypeSafe(ctx);
  value = { type: "key", key: "secret-two" };
  assert.notEqual((await resolveTypeSafe(ctx)).identity, first.identity);
  assert.equal(first.identity.includes("secret"), false);
  connection = { type: "env", names: ["TYPESAFE_API_KEY"] };
  assert.equal((await resolveTypeSafe(ctx)).apiKey, "secret-two");
  for (value of [undefined, { type: "key", key: " " }, { type: "oauth", access: "secret" }]) {
    assert.equal(await resolveTypeSafe(ctx), undefined);
  }
  connection = undefined;
  assert.equal(await resolveTypeSafe(ctx), undefined);
});

test("session normalization uses live location, explicit selections, and active drain", async () => {
  const selected = { id: "m1", type: "model-switched", model: { id: "x", providerID: "p" } };
  const history = [selected, { id: "u", type: "user", text: "in progress" }];
  const ctx = { session: {
    get: async () => ({ id: "s", location: { directory: "/moved" }, model: history[0].model }),
    context: async () => ({ data: history }),
  } };
  const view = await readSessionView(ctx, "s");
  assert.equal(view.directory, "/moved");
  assert.equal(view.busy, true);
  assert.deepEqual(view.selectionEvents, [selected]);
  assert.deepEqual(unwrap({ data: [1] }), [1]);
});

test("catalog reads carry the session location to each domain", async () => {
  const list = async input => { assert.deepEqual(input, { location: { directory: "/other" } }); return { data: [1] }; };
  const ctx = { agent: { list }, model: { list }, skill: { list } };
  assert.deepEqual(await readCatalogs(ctx, "/other"), { agents: [1], models: [1], skills: [1] });
});
