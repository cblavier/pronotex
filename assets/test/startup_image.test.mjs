import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const root = readFileSync(new URL('../../lib/pronotex_web/components/layouts/root.html.heex', import.meta.url), 'utf8');
const source = root.match(/<script id="select-startup-image">([\s\S]*?)<\/script>/)[1];
const images = readFileSync(new URL('../../lib/pronotex_web/components/layouts/startup_images.html.heex', import.meta.url), 'utf8');

function launch(width, height, ratio) {
  let portrait = true;
  const queries = [];
  const links = [...images.matchAll(/media="([^"]+)"\s+href=\{~p"([^"]+)"\}/g)].map(([, media, href]) => ({
    media, href, attached: true,
    remove() { this.attached = false; },
    removeAttribute(name) { assert.equal(name, 'media'); this.media = undefined; }
  }));
  const document = {
    querySelectorAll: () => links,
    currentScript: {before(link) { link.attached = true; }}
  };
  const window = {matchMedia(media) {
    const [, w, h, dpr, orientation] = media.match(/device-width: (\d+)px.*device-height: (\d+)px.*pixel-ratio: (\d+).*orientation: (portrait|landscape)/);
    const query = {
      get matches() { return +w === width && +h === height && +dpr === ratio && (orientation === 'portrait') === portrait; },
      addEventListener(event, callback) { assert.equal(event, 'change'); this.callback = callback; }
    };
    queries.push(query);
    return query;
  }};
  vm.runInNewContext(source, {document, window});
  return {
    active: () => links.filter(link => link.attached),
    rotate() { portrait = !portrait; queries.forEach(query => query.callback()); }
  };
}

test('the reported iPhone screen gets one unconditional image, including after rotation', () => {
  const page = launch(430, 932, 3);
  assert.equal(page.active().length, 1);
  assert.equal(page.active()[0].href, '/images/startup/launch-1290x2796.png');
  assert.equal(page.active()[0].media, undefined);
  page.rotate();
  assert.equal(page.active().length, 1);
  assert.equal(page.active()[0].href, '/images/startup/launch-2796x1290.png');
  assert.equal(page.active()[0].media, undefined);
  page.rotate();
  assert.equal(page.active().length, 1);
  assert.equal(page.active()[0].href, '/images/startup/launch-1290x2796.png');
});

test('an unsupported screen keeps the original declarations instead of choosing a wrong image', () => {
  const page = launch(999, 999, 1);
  assert.equal(page.active().length, 44);
  assert.ok(page.active().every(link => link.media));
});
