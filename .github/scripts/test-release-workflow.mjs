import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../..');
const parsed = spawnSync('ruby', ['-rjson', '-rpsych', '-e', 'print JSON.generate(Psych.safe_load(File.read(ARGV[0])))', path.join(root, '.github/workflows/release.yml')], { encoding: 'utf8' });
assert.equal(parsed.status, 0, parsed.stderr);
const workflow = JSON.parse(parsed.stdout);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const resolveScript = workflow.jobs.resolve.steps[0].with.script;
const sha = 'a'.repeat(40);
const object = 'b'.repeat(40);
const hash = value => createHash('sha256').update(value).digest('hex');

async function resolve({ event = 'workflow_dispatch', ref = 'refs/heads/main', dry = 'true', protectedBranch = true, type = 'tag', exists = false, ancestry = 'identical', head = sha } = {}) {
  const seen = [];
  const github = { rest: {
    repos: {
      get: async () => ({ data: { default_branch: 'main' } }),
      getBranch: async () => ({ data: { protected: protectedBranch, commit: { sha: head } } }),
      compareCommitsWithBasehead: async () => ({ data: { status: ancestry } }),
      getReleaseByTag: async () => { seen.push('release'); if (!exists) throw Object.assign(new Error('missing'), { status: 404 }); return { data: {} }; },
    },
    git: {
      getRef: async () => { seen.push('tag'); return { data: { object: { type, sha: object } } }; },
      getTag: async () => ({ data: { object: { type: 'commit', sha } } }),
    },
  } };
  const outputs = {};
  await new AsyncFunction('github', 'context', 'core', 'process', resolveScript)(github,
    { eventName: event, ref, sha, repo: { owner: 'example', repo: 'AXorcist' } },
    { setOutput: (key, value) => { outputs[key] = value; } },
    { env: { VERSION: '0.2.2', DRY_RUN: dry } });
  return { outputs, seen };
}

test('dry-run current main never reads or modifies an old tag/release', async () => {
  const { outputs, seen } = await resolve({ exists: true, type: 'commit' });
  assert.equal(outputs.dry, 'true');
  assert.equal(outputs.object, '');
  assert.deepEqual(seen, []);
});
test('rehearsal rejects unprotected, stale and non-default refs', async () => {
  await assert.rejects(resolve({ protectedBranch: false }), /protected/);
  await assert.rejects(resolve({ head: 'c'.repeat(40) }), /current protected/);
  await assert.rejects(resolve({ ref: 'refs/heads/topic' }), /current protected/);
});
test('dispatch cannot publish', async () => {
  await assert.rejects(resolve({ dry: 'false' }), /rehearsal only/);
});
test('live tags must be annotated, unpublished and on protected main', async () => {
  const input = { event: 'push', ref: 'refs/tags/v0.2.2', dry: '' };
  assert.equal((await resolve(input)).outputs.object, object);
  await assert.rejects(resolve({ ...input, type: 'commit' }), /Annotated/);
  await assert.rejects(resolve({ ...input, exists: true }), /already released/);
  await assert.rejects(resolve({ ...input, ancestry: 'diverged' }), /outside protected/);
});
test('shared gate verifies signed tags and exact push CI; dry path cannot publish', () => {
  const source = workflow.jobs['source-proof'];
  assert.match(source.uses, /release-source.yml@v1$/);
  assert.equal(source.with.dry_run, true);
  assert.equal(source.with['require-signed-tag'], true);
  assert.equal(source.with['strict-checks'], true);
  assert.equal(source.with['ci-check-events'], '["push"]');
  assert.equal(workflow.jobs.publish.if, "needs.resolve.outputs.dry == 'false'");
  assert.ok(workflow.jobs.homebrew.needs.includes('publish'));
  assert.deepEqual(workflow.jobs.verify.permissions, { actions: 'read' });
  assert.ok(workflow.jobs.verify.steps[0].with['artifact-ids']);
  assert.equal(workflow.jobs.sign.steps.some(step => step.uses?.startsWith('actions/checkout')), false);
  assert.equal(workflow.jobs.publish.steps.some(step => step.uses?.startsWith('actions/checkout')), false);
});

function publishFixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'axorc-release-proof-'));
  fs.mkdirSync(path.join(dir, 'payload'));
  const notes = Buffer.from('## [0.2.2] - 2026-10-10\n\nSynthetic fixture.\n');
  const inventory = Buffer.from(JSON.stringify({ repository: 'example/AXorcist', commit: sha, tag: 'v0.2.2', assets: [{ name: 'RELEASE-NOTES.md', sha256: hash(notes), size: notes.length }] }));
  const sums = Buffer.from('synthetic checksums');
  for (const [name, value] of [['RELEASE-NOTES.md', notes], ['ASSET-INVENTORY.json', inventory], ['SHA256SUMS', sums]]) fs.writeFileSync(path.join(dir, 'payload', name), value);
  for (const arch of ['arm64', 'x86_64']) {
    fs.mkdirSync(path.join(dir, 'attestations', arch), { recursive: true });
    fs.writeFileSync(path.join(dir, 'attestations', arch, 'ASSET-INVENTORY.json'), inventory);
    fs.writeFileSync(path.join(dir, 'attestations', arch, 'SHA256SUMS'), sums);
  }
  return dir;
}
async function publish(dir, moved = false) {
  const writes = [];
  const mockFs = {
    readFileSync: (file, ...args) => fs.readFileSync(path.join(dir, file), ...args),
    readdirSync: file => fs.readdirSync(path.join(dir, file)),
  };
  const github = { rest: {
    git: {
      getRef: async () => ({ data: { object: { type: 'tag', sha: moved ? 'c'.repeat(40) : object } } }),
      getTag: async () => ({ data: { object: { type: 'commit', sha } } }),
    },
    repos: {
      getReleaseByTag: async () => { throw Object.assign(new Error('missing'), { status: 404 }); },
      createRelease: async () => { writes.push('create'); throw new Error('stop at first write'); },
    },
  } };
  const script = workflow.jobs.publish.steps.at(-1).with.script;
  const modules = { fs: mockFs, path, crypto: { createHash } };
  await new AsyncFunction('github', 'context', 'core', 'process', 'require', script)(github,
    { sha, repo: { owner: 'example', repo: 'AXorcist' } }, {},
    { env: { TAG: 'v0.2.2', TAG_OBJECT: object } }, name => modules[name]);
  return writes;
}
test('publisher rejects moved tags and verifier disagreement before any write', async () => {
  const dir = publishFixture();
  try {
    await assert.rejects(publish(dir, true), /Tag moved/);
    fs.appendFileSync(path.join(dir, 'attestations/arm64/SHA256SUMS'), 'tamper');
    await assert.rejects(publish(dir), /Verifier disagreement/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
test('publisher refuses payload mutation before any write', async () => {
  const dir = publishFixture();
  try {
    fs.appendFileSync(path.join(dir, 'payload/RELEASE-NOTES.md'), 'tamper');
    await assert.rejects(publish(dir), /Payload mismatch/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('ZIP handoff uses the supported template contract, not tar-only explicit assets', async () => {
  let dispatched;
  const inventory = { repository: 'example/AXorcist', commit: sha, tag: 'v0.2.2', assets: ['arm64', 'x86_64'].map(arch => ({ name: `axorc-0.2.2-macos-${arch}.zip`, sha256: 'a'.repeat(64) })) };
  const github = { rest: { actions: { createWorkflowDispatch: async value => { dispatched = value; throw new Error('stop before waiting'); } } } };
  const script = workflow.jobs.homebrew.steps.at(-1).with.script;
  await assert.rejects(new AsyncFunction('github', 'context', 'core', 'process', 'require', script)(github,
    { sha, runId: 123, repo: { owner: 'example', repo: 'AXorcist' } }, {},
    { env: { TAG: 'v0.2.2', GITHUB_RUN_ATTEMPT: '1' } }, () => ({ readFileSync: () => JSON.stringify(inventory) })), /stop before waiting/);
  assert.equal(dispatched.inputs.assets, undefined);
  assert.equal(dispatched.inputs.artifact_template, 'axorc-{version}-{target}.zip');
  assert.equal(dispatched.inputs.target_aliases, 'darwin_arm64=macos-arm64,darwin_amd64=macos-x86_64');
});

test('ticket verification waits for propagation but never accepts a missing ticket', () => {
  const sign = workflow.jobs.sign.steps.find(step => step.name === 'Sign, notarize and freeze all three archives').run;
  const verify = workflow.jobs.verify.steps.find(step => step.run).run;
  const extract = script => script.match(/verify_notarization\(\) \{[\s\S]*?\n\}/)?.[0];
  const fn = extract(sign);
  assert.ok(fn);
  assert.equal(extract(verify), fn);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'notary-propagation-'));
  try {
    fs.writeFileSync(path.join(dir, 'codesign'), '#!/bin/bash\n[[ "$*" == "--verify --strict --check-notarization -R=notarized fixture" ]] || exit 42\nn=$(cat "$COUNT" 2>/dev/null || echo 0)\nn=$((n+1))\necho "$n" > "$COUNT"\n[[ "$n" -ge "$SUCCEED_AT" ]]\n', { mode: 0o755 });
    fs.writeFileSync(path.join(dir, 'sleep'), '#!/bin/bash\nexit 0\n', { mode: 0o755 });
    for (const [succeedAt, expectedCode, expectedAttempts] of [[3, 0, 3], [31, 1, 30]]) {
      const counter = path.join(dir, `counter-${succeedAt}`);
      const result = spawnSync('/bin/bash', ['-e', '-c', `${fn}\nverify_notarization fixture`], { encoding: 'utf8', env: { ...process.env, PATH: `${dir}:/usr/bin:/bin`, COUNT: counter, SUCCEED_AT: String(succeedAt) } });
      assert.equal(result.status, expectedCode, result.stderr);
      assert.equal(Number(fs.readFileSync(counter, 'utf8')), expectedAttempts);
    }
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
