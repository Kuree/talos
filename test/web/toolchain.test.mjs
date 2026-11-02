// REQUIRES: node
// RUN: %node --experimental-default-type=module %s

import assert from 'node:assert/strict';

await import('../../web/toolchain.js');

assert.equal(typeof globalThis.installTalosToolchain, 'function');

const directories = new Set();
const files = new Map();
const loaded = [];
const FS = {
  mkdir(path) {
    if (directories.has(path)) throw new Error('already exists');
    directories.add(path);
  },
  writeFile(path, data) { files.set(path, data); },
};

await globalThis.installTalosToolchain({ FS }, {
  load: async (name) => {
    loaded.push(name);
    return new TextEncoder().encode(name);
  },
});

assert.deepEqual(loaded, [
  'libtalos_rt.a', 'libstubs.a', 'libnoexit.a', 'libc.a', 'libdlmalloc.a',
  'libc++.a', 'libc++abi.a', 'libcompiler_rt.a', 'libunwind.a',
]);
const target = '/lib/talos/targets/wasm32-unknown-emscripten';
assert.equal(new TextDecoder().decode(files.get(`${target}/libtalos_rt.a`)),
  'libtalos_rt.a');
for (const name of loaded.slice(1)) {
  assert.ok(files.has(`/sysroot/lib/wasm32-emscripten/${name}`), name);
}
assert.equal(files.get(`${target}/.complete`), 'web toolchain\n');
assert.ok(directories.has(target));
assert.ok(directories.has('/sysroot/lib/wasm32-emscripten'));

// All archives start before the compiler or any download finishes. Readiness
// waits for every archive, even when they complete out of order.
{
  let resolveModule;
  const driver = new Promise((resolve) => { resolveModule = resolve; });
  const downloads = new Map();
  const installed = new Map();
  const mod = { FS: { mkdir() {}, writeFile: (path, data) => installed.set(path, data) } };
  const ready = globalThis.installTalosToolchain(driver, {
    load: (name) => new Promise((resolve) => { downloads.set(name, resolve); }),
  });
  assert.deepEqual([...downloads.keys()], loaded);
  for (const name of loaded.slice(1).reverse()) downloads.get(name)(name);
  resolveModule(mod);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(installed.size, loaded.length - 1);
  assert.equal(installed.has(`${target}/.complete`), false);
  downloads.get(loaded[0])(loaded[0]);
  assert.equal(await ready, mod);
  assert.equal(installed.size, loaded.length + 1);
  assert.equal(installed.get(`${target}/.complete`), 'web toolchain\n');
}

files.delete(`${target}/.complete`);
await assert.rejects(
  globalThis.installTalosToolchain({ FS }, {
    load: async (name) => { throw new Error(`missing ${name}`); },
  }),
  /missing libtalos_rt\.a/,
);
assert.equal(files.has(`${target}/.complete`), false);

await assert.rejects(
  globalThis.installTalosToolchain(Promise.reject(new Error('compiler unavailable')), {
    load: async () => new Uint8Array(),
  }),
  /compiler unavailable/,
);

console.log('web compiler toolchain installation OK');
