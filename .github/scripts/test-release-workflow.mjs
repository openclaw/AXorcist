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
function publisher(dir, releases = []) {
  const state = { releases, writes: [], pages: [], downloads: [], moved: false, failUploadAt: 0, remoteTampered: false, draftChanged: false };
  let nextId = 1000;
  const mockFs = {
    readFileSync: (file, ...args) => fs.readFileSync(path.join(dir, file), ...args),
    readdirSync: file => fs.readdirSync(path.join(dir, file)),
  };
  const github = { rest: {
    git: {
      getRef: async () => ({ data: { object: { type: 'tag', sha: state.moved ? 'c'.repeat(40) : object } } }),
      getTag: async () => ({ data: { object: { type: 'commit', sha } } }),
    },
    repos: {
      getReleaseByTag: async () => {
        if (state.publishedLookup) return { data: state.publishedLookup };
        throw Object.assign(new Error('missing'), { status: 404 });
      },
      listReleases: async ({ page, per_page }) => {
        assert.equal(per_page, 100);
        state.pages.push(page);
        return { data: state.listPage ? await state.listPage(page) : state.releases.slice((page - 1) * per_page, page * per_page) };
      },
      createRelease: async input => {
        state.writes.push('create');
        const release = { ...input, id: nextId++, html_url: 'https://example.invalid/release', assets: [] };
        state.releases.push(release);
        return { data: release };
      },
      uploadReleaseAsset: async ({ release_id, name, data }) => {
        state.writes.push(`upload:${name}`);
        const release = state.releases.find(r => r.id === release_id);
        if (release.assets.length + 1 === state.failUploadAt) throw new Error('Upload interrupted');
        release.assets.push({ id: nextId++, name, size: data.length, bytes: Buffer.from(data) });
      },
      listReleaseAssets: async ({ release_id }) => ({ data: state.releases.find(r => r.id === release_id).assets }),
      getRelease: async ({ release_id }) => {
        const release = state.releases.find(r => r.id === release_id);
        return { data: state.draftChanged ? { ...release, body: 'changed' } : release };
      },
      updateRelease: async ({ release_id, draft }) => {
        state.writes.push('publish');
        state.releases.find(r => r.id === release_id).draft = draft;
      },
    },
  }, request: async (route, { asset_id }) => {
    assert.equal(route, 'GET /repos/{owner}/{repo}/releases/assets/{asset_id}');
    const asset = state.releases.flatMap(r => r.assets ?? []).find(a => a.id === asset_id);
    state.downloads.push(asset.name);
    return { data: state.remoteTampered ? Buffer.from('tamper') : asset.bytes };
  } };
  const script = workflow.jobs.publish.steps.at(-1).with.script;
  const modules = { fs: mockFs, path, crypto: { createHash } };
  state.run = () => new AsyncFunction('github', 'context', 'core', 'process', 'require', script)(github,
    { sha, repo: { owner: 'example', repo: 'AXorcist' } }, { summary: { addLink() {}, async write() {} } },
    { env: { TAG: 'v0.2.2', TAG_OBJECT: object } }, name => modules[name]);
  return state;
}
function fixture(t, releases) {
  const dir = publishFixture();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return { dir, state: publisher(dir, releases) };
}
const unrelatedReleases = count => Array.from({ length: count }, (_, id) => ({ id, tag_name: `v0.0.${id}`, draft: true }));

test('fresh publisher uploads, downloads and verifies every asset before publishing', async t => {
  const { state } = fixture(t);
  await state.run();
  assert.deepEqual(state.writes, ['create', 'upload:RELEASE-NOTES.md', 'upload:ASSET-INVENTORY.json', 'upload:SHA256SUMS', 'publish']);
  assert.deepEqual(state.downloads, ['RELEASE-NOTES.md', 'ASSET-INVENTORY.json', 'SHA256SUMS']);
  assert.equal(state.releases.length, 1);
  assert.equal(state.releases[0].draft, false);
});
test('interrupted upload leaves a partial draft that retry refuses without further writes', async t => {
  const { state } = fixture(t);
  state.failUploadAt = 2;
  await assert.rejects(state.run(), /Upload interrupted/);
  assert.equal(state.releases.length, 1);
  assert.equal(state.releases[0].draft, true);
  assert.equal(state.releases[0].assets.length, 1);
  const writes = [...state.writes];
  state.failUploadAt = 0;
  await assert.rejects(state.run(), /Release already exists/);
  assert.deepEqual(state.writes, writes);
  assert.equal(state.releases.length, 1);
  assert.equal(state.releases[0].assets.length, 1);
});
for (const draft of [true, false]) {
  for (const preceding of [0, 100, 200]) {
    test(`publisher refuses matching ${draft ? 'draft' : 'published release'} on page ${preceding / 100 + 1}`, async t => {
      const { state } = fixture(t, [...unrelatedReleases(preceding), { tag_name: 'v0.2.2', draft }]);
      await assert.rejects(state.run(), /Release already exists/);
      assert.deepEqual(state.writes, []);
      assert.deepEqual(state.pages, Array.from({ length: preceding / 100 + 1 }, (_, n) => n + 1));
    });
  }
}
test('publisher refuses mismatched and ambiguous existing drafts', async t => {
  const { state } = fixture(t, [
    { tag_name: 'v0.2.2', draft: true, body: 'different notes', target_commitish: 'c'.repeat(40), assets: [] },
    { tag_name: 'v0.2.2', draft: true, assets: [{ name: 'unknown.zip' }] },
  ]);
  await assert.rejects(state.run(), /Release already exists/);
  assert.deepEqual(state.writes, []);
});
test('publisher permits unrelated drafts and finishes an exact full listing page', async t => {
  const { state } = fixture(t, unrelatedReleases(100));
  await state.run();
  assert.deepEqual(state.pages, [1, 2]);
  assert.equal(state.releases.at(-1).draft, false);
  assert.equal(state.writes.at(-1), 'publish');
});
test('publisher preserves the published tag refusal', async t => {
  const { state } = fixture(t);
  state.publishedLookup = { tag_name: 'v0.2.2', draft: false };
  await assert.rejects(state.run(), /Version already released/);
  assert.deepEqual(state.pages, []);
  assert.deepEqual(state.writes, []);
});
test('malformed release listings fail before any write', async t => {
  for (const listing of [null, {}, [null], [{}], [{ tag_name: '', draft: true }], [{ tag_name: 22, draft: true }], [{ tag_name: 'other', draft: 'true' }], unrelatedReleases(101)]) {
    const { state } = fixture(t);
    state.listPage = () => listing;
    await assert.rejects(state.run(), /Invalid release listing/);
    assert.deepEqual(state.writes, []);
  }
});
test('listing errors and malformed later pages fail before any write', async t => {
  for (const laterPage of [() => { throw new Error('Listing unavailable'); }, () => ({ releases: [] })]) {
    const { state } = fixture(t);
    state.listPage = page => page === 1 ? unrelatedReleases(100) : laterPage();
    await assert.rejects(state.run(), /Listing unavailable|Invalid release listing/);
    assert.deepEqual(state.pages, [1, 2]);
    assert.deepEqual(state.writes, []);
  }
});
test('publisher rejects moved tags and verifier disagreement before any write', async t => {
  const { dir, state } = fixture(t);
  state.moved = true;
  await assert.rejects(state.run(), /Tag moved/);
  assert.deepEqual(state.writes, []);
  state.moved = false;
  fs.appendFileSync(path.join(dir, 'attestations/arm64/SHA256SUMS'), 'tamper');
  await assert.rejects(state.run(), /Verifier disagreement/);
  assert.deepEqual(state.writes, []);
});
test('publisher refuses payload mutation before any write', async t => {
  const { dir, state } = fixture(t);
  fs.appendFileSync(path.join(dir, 'payload/RELEASE-NOTES.md'), 'tamper');
  await assert.rejects(state.run(), /Payload mismatch/);
  assert.deepEqual(state.writes, []);
});
test('publisher refuses remote digest and final draft changes before publishing', async t => {
  for (const [fault, message] of [['remoteTampered', /Remote digest mismatch/], ['draftChanged', /Draft changed/]]) {
    const { state } = fixture(t);
    state[fault] = true;
    await assert.rejects(state.run(), message);
    assert.ok(state.writes.includes('create'));
    assert.ok(!state.writes.includes('publish'));
    assert.equal(state.releases[0].draft, true);
  }
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
  const verify = workflow.jobs.verify.steps.find(step => step.name === 'Verify bytes, signatures, tickets and architecture smoke').run;
  const extract = script => script.match(/verify_notarization\(\) \{[\s\S]*?\n\}/)?.[0];
  const fn = extract(sign);
  assert.ok(fn);
  assert.equal(extract(verify), fn);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'notary-propagation-'));
  try {
    fs.writeFileSync(path.join(dir, 'codesign'), '#!/bin/bash\n[[ "$*" == "--verify --strict --check-notarization -R=notarized --architecture arm64 fixture" || "$*" == "--verify --strict --check-notarization -R=notarized --architecture x86_64 fixture" ]] || exit 42\ncounter="$COUNT-${6}"\nn=$(cat "$counter" 2>/dev/null || echo 0)\nn=$((n+1))\necho "$n" > "$counter"\n[[ "$n" -ge "$SUCCEED_AT" ]]\n', { mode: 0o755 });
    fs.writeFileSync(path.join(dir, 'lipo'), '#!/bin/bash\nprintf "arm64 x86_64\\n"\n', { mode: 0o755 });
    fs.writeFileSync(path.join(dir, 'sleep'), '#!/bin/bash\nexit 0\n', { mode: 0o755 });
    for (const [succeedAt, expectedCode, expectedAttempts] of [[3, 0, 3], [91, 1, 90]]) {
      const counter = path.join(dir, `counter-${succeedAt}`);
      const result = spawnSync('/bin/bash', ['-e', '-c', `${fn}\nverify_notarization fixture`], { encoding: 'utf8', env: { ...process.env, PATH: `${dir}:/usr/bin:/bin`, COUNT: counter, SUCCEED_AT: String(succeedAt) } });
      assert.equal(result.status, expectedCode, result.stderr);
      assert.equal(Number(fs.readFileSync(counter + '-arm64', 'utf8')), expectedAttempts);
      if (expectedCode === 0) assert.equal(Number(fs.readFileSync(counter + '-x86_64', 'utf8')), expectedAttempts);
      else assert.equal(fs.existsSync(counter + '-x86_64'), false);
    }
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
