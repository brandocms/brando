// Run from the repository root. Override these paths when dependencies live in another checkout.
const path = require('node:path');
const playwrightPath = path.resolve(process.env.BRANDO_AUDIT_PLAYWRIGHT || 'e2e/e2e/playwright/node_modules/@playwright/test');
const liveViewPath = path.resolve(process.env.BRANDO_AUDIT_LIVEVIEW || 'deps/phoenix_live_view');
const phoenixPath = path.resolve(process.env.BRANDO_AUDIT_PHOENIX || 'deps/phoenix');
const { chromium } = require(playwrightPath);
const fs = require('fs');
const assert = require('node:assert/strict');

assert.match(fs.readFileSync(path.join(liveViewPath, 'mix.exs'), 'utf8'), /@version \"1\.2\.11\"/);

(async () => {
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    await page.route('http://audit.local/**', route => route.fulfill({contentType: 'text/html', body: '<html></html>'}));
    await page.goto('http://audit.local/');
    await page.setContent('<div id="audit-view" data-phx-session="test" data-phx-root-id="audit-view"></div>');
    await page.addScriptTag({path: path.join(phoenixPath, 'priv/static/phoenix.js')});
    const source = fs.readFileSync(path.join(liveViewPath, 'priv/static/phoenix_live_view.cjs.js'), 'utf8');
    await page.addScriptTag({content: 'var module = {exports: {}};\n' + source + '\nwindow.audit = {DOMPatch, DOM, View, LiveSocket};'});
    const result = await page.evaluate(() => {
      const {DOMPatch, View, LiveSocket} = window.audit;
      const root = document.getElementById('audit-view');
      const liveSocket = new LiveSocket('/live', window.Phoenix.Socket);
      const view = new View(root, liveSocket, null);
      const apply = (html, streams = new Set()) => new DOMPatch(view, root, `<div id="audit-view" data-phx-session="test" data-phx-root-id="audit-view">${html}</div>`, streams, null).perform(false);
      const html = (active, offline) => `<div id="modal-online" phx-update="stream">${active ? '<div id="active-1_modal">Online</div>' : ''}</div><div id="modal-offline" phx-update="stream">${offline ? '<div id="inactive-1_modal">Offline</div>' : ''}</div><div id="active" phx-update="stream">${active ? '<div id="active-1">Online</div>' : ''}</div><div id="inactive" phx-update="stream">${offline ? '<div id="inactive-1">Offline</div>' : ''}</div>`;
      apply(html(true, false), new Set([['0', [['active-1', -1, null]], [], true], ['1', [], [], true]]));
      const modalRef = document.getElementById('active-1_modal').getAttribute('data-phx-stream');
      apply(html(false, true), new Set([['0', [], [], true], ['1', [['inactive-1', -1, null]], [], true]]));
      const staleModal = !!document.getElementById('active-1_modal');
      const removedAvatar = !document.getElementById('active-1');
      const bothModalRows = !!document.getElementById('inactive-1_modal') && staleModal;

      root.innerHTML = '<div id="datepicker"><div id="ignored" phx-update="ignore"><input type="hidden" name="date" value="2026-09-01"></div></div>';
      apply('<div id="datepicker"><div id="ignored" phx-update="ignore"><input type="hidden" name="date" value="2026-09-08"></div></div>');
      const ignoredDate = root.querySelector('input').value;
      root.innerHTML = '<div id="code"><textarea>old source</textarea><div id="editor-target" phx-update="ignore"><div class="editor">old source</div></div></div>';
      apply('<div id="code"><textarea>restored source</textarea><div id="editor-target" phx-update="ignore"><div class="editor"></div></div></div>');
      const textarea = root.querySelector('textarea').value;
      const editor = root.querySelector('.editor').textContent;
      return {modalRef, staleModal, removedAvatar, bothModalRows, ignoredDate, textarea, editor};
    });
    assert.equal(result.modalRef, null);
    assert.equal(result.staleModal, true);
    assert.equal(result.removedAvatar, true);
    assert.equal(result.bothModalRows, true);
    assert.equal(result.ignoredDate, '2026-09-01');
    assert.equal(result.textarea, 'restored source');
    assert.equal(result.editor, 'old source');
    console.log(JSON.stringify(result, null, 2));
    console.log('7 DOM assertions passed against LiveView 1.2.11 bundle');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
