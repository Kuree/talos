// Installs the target files used by the compiler's in-process wasm linker.
// This is a classic script so compiler-worker.js can load it with
// importScripts; the smoke test uses the same global entry point under Node.

(() => {
  const TARGET = '/lib/talos/targets/wasm32-unknown-emscripten';
  const ASSETS = [
    ['libtalos_rt.a', `${TARGET}/libtalos_rt.a`],
    ['libstubs.a', '/sysroot/lib/wasm32-emscripten/libstubs.a'],
    ['libnoexit.a', '/sysroot/lib/wasm32-emscripten/libnoexit.a'],
    ['libc.a', '/sysroot/lib/wasm32-emscripten/libc.a'],
    ['libdlmalloc.a', '/sysroot/lib/wasm32-emscripten/libdlmalloc.a'],
    ['libc++.a', '/sysroot/lib/wasm32-emscripten/libc++.a'],
    ['libc++abi.a', '/sysroot/lib/wasm32-emscripten/libc++abi.a'],
    ['libcompiler_rt.a', '/sysroot/lib/wasm32-emscripten/libcompiler_rt.a'],
    ['libunwind.a', '/sysroot/lib/wasm32-emscripten/libunwind.a'],
  ];

  function ensureDirectory(FS, path) {
    let current = '';
    for (const component of path.split('/').filter(Boolean)) {
      current += `/${component}`;
      try { FS.mkdir(current); } catch { /* already exists */ }
    }
  }

  async function defaultLoad(name) {
    const response = await fetch(new URL(`./toolchain/${name}`, self.location.href));
    if (!response.ok) throw new Error(`failed to load ${name}: HTTP ${response.status}`);
    return new Uint8Array(await response.arrayBuffer());
  }

  globalThis.installTalosToolchain = async function installTalosToolchain(
    mod, { load = defaultLoad } = {},
  ) {
    // Accept a module promise so archives download alongside the compiler.
    await Promise.all(ASSETS.map(async ([name, path]) => {
      const [driver, data] = await Promise.all([mod, load(name)]);
      ensureDirectory(driver.FS, path.slice(0, path.lastIndexOf('/')));
      driver.FS.writeFile(path, data);
    }));
    const driver = await mod;
    driver.FS.writeFile(`${TARGET}/.complete`, 'web toolchain\n');
    return driver;
  };
})();
