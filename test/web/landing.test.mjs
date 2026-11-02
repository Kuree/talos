// REQUIRES: node
// RUN: %node %s

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../../web/landing.js', import.meta.url), 'utf8');

function landing({ observers = true, hidden = false } = {}) {
  const attributes = new Set();
  const events = new Map();
  const simulation = {};
  let observer;
  class IntersectionObserver {
    constructor(callback) { observer = this; this.callback = callback; }
    observe(element) { assert.equal(element, simulation); }
    visible(isIntersecting) { this.callback([{ isIntersecting }]); }
  }
  const document = {
    hidden,
    documentElement: {
      toggleAttribute(name, enabled) {
        if (enabled) attributes.add(name);
        else attributes.delete(name);
      },
    },
    getElementById: () => ({}),
    querySelector: () => simulation,
    querySelectorAll: () => [],
    addEventListener: (type, callback) => events.set(type, callback),
  };
  const window = observers ? { IntersectionObserver } : {};
  vm.runInNewContext(source, { document, window, IntersectionObserver });
  return {
    get paused() { return attributes.has('data-simulation-paused'); },
    visible: (value) => observer.visible(value),
    hide(value) { document.hidden = value; events.get('visibilitychange')(); },
  };
}

const page = landing();
assert.equal(page.paused, false);
page.visible(false);
assert.equal(page.paused, true);
page.hide(true);
page.visible(true);
assert.equal(page.paused, true, 'being onscreen must not resume a hidden tab');
page.hide(false);
assert.equal(page.paused, false);
page.visible(false);
page.hide(false);
assert.equal(page.paused, true, 'a visible tab must not resume an offscreen demo');
page.visible(true);
assert.equal(page.paused, false);

const fallback = landing({ observers: false, hidden: true });
assert.equal(fallback.paused, true);
fallback.hide(false);
assert.equal(fallback.paused, false);

console.log('landing animation visibility and browser fallback OK');
