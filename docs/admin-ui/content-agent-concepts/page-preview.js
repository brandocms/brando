// Illustrative page templates for reviewing the interaction, not real site renders.
function workspacePreview() {
  const c = changes[state.previewEntry];
  const mobile = state.previewDevice === 'mobile';
  return `<button class="mobile-chat-toggle" data-action="toggle-chat" aria-expanded="${state.mobileChat}">${icon('chat')}Sommerro conversation<span>${state.mobileChat?'Hide conversation':'Show conversation'}</span></button>
    <div class="workspace-body">${conversation()}
      <section class="review-workspace page-preview-workspace" aria-label="Page preview">
        <div class="page-preview-heading">
          <button class="preview-back" data-preview-action="back">${icon('arrow')}All changes</button>
          <span class="eyebrow">Proposal 01 · not applied</span>
        </div>
        <div class="preview-title-row"><div><h1>See it on the page.</h1><p>Your proposed content, in context.</p></div>${pill(c.action==='Create'?'New draft':'Updates live page',c.action==='Create'?'green':'amber')}</div>
        <nav class="preview-destinations" aria-label="Pages to preview">${changes.map((entry,i)=>`<button class="preview-destination ${state.previewEntry===i?'selected':''}" data-page-preview="${entry.id}" aria-pressed="${state.previewEntry===i}"><img src="${entry.asset.src}" alt=""><span>${entry.title}<small>${entry.action==='Create'?'New case':'1 block added'}</small></span>${icon('chevron')}</button>`).join('')}</nav>
        <div class="page-preview-controls">
          <div class="preview-version-switch" aria-label="Preview version"><button data-preview-action="before" class="${state.previewBefore?'selected':''}" aria-pressed="${state.previewBefore}">Before</button><button data-preview-action="after" class="${!state.previewBefore?'selected':''}" aria-pressed="${!state.previewBefore}">Proposed</button></div>
          <div class="preview-device-switch" aria-label="Preview viewport"><button data-preview-action="desktop" class="${!mobile?'selected':''}" aria-pressed="${!mobile}" aria-label="Desktop preview"><svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 4h18v13H3zM8 21h8M12 17v4"/></svg><span>Desktop</span></button><button data-preview-action="mobile" class="${mobile?'selected':''}" aria-pressed="${mobile}" aria-label="Mobile preview"><svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 2h10v20H7zM11 18h2"/></svg><span>Mobile</span></button></div>
          <label class="preview-highlight-control"><input type="checkbox" ${state.previewHighlight?'checked':''} data-preview-highlight>Show changes</label>
        </div>
        <div class="page-preview-stage ${mobile?'device-mobile':''}">
          <div class="page-preview-window">
            <div class="preview-address"><span class="preview-window-dots"><i></i><i></i><i></i></span>${icon('lock')}<span>studio.example${c.path}</span><span class="preview-address-state">${state.previewBefore?'Before':'Proposed'}</span></div>
            <div class="page-preview-scroll" tabindex="0" aria-label="Scrollable page preview">
              ${proposalPage(c)}
            </div>
          </div>
        </div>
        <div class="page-preview-caption"><span>${icon('image')}Illustrative mockup · the product will use your site’s templates.</span><button data-change="${c.id}">Review fields${icon('chevron')}</button></div>
        <div class="page-preview-change-note">${icon(state.previewBefore?'history':'check')}<span>${state.previewBefore?(c.action==='Create'?'Sommerro has not been created yet.':'Current saved content. No proposed changes are shown.'):(c.action==='Create'?'New draft case · image2 as cover · not published':`Adds one Case block after the introduction · ${c.asset.alias}`)}</span></div>
        <div class="review-space"></div>${applyBar()}
      </section>
    </div>`;
}

function proposalPage(c) {
  if (c.action === 'Create' && state.previewBefore) {
    return `<div class="preview-new-entry-empty">${icon('pages')}<h2>A new page starts here.</h2><p>Sommerro doesn’t exist yet.<br>Choose Proposed to preview the new draft.</p></div>`;
  }
  const highlight = state.previewHighlight && !state.previewBefore;
  const casePage = c.action === 'Create';
  return `<div class="proposal-site ${state.previewDevice==='mobile'?'narrow':''}">
    <div class="proposal-site-nav"><span class="proposal-site-wordmark">STUDIO<span>®</span></span><div>Selected work <span>About us</span> <span>Get in touch ↗</span></div></div>
    <div class="proposal-site-intro"><div><span class="proposal-site-kicker">${casePage?'Hospitality / Oslo, Norway':'Our practice / '+(c.id==='identity'?'01':'02')}</span><h2>${casePage?'Sommerro.':c.title+'.'}</h2></div><p>${casePage?'A place to come together. An identity rooted in the warmth of everyday encounters.':c.id==='identity'?'Distinctive identities.<br>Built with purpose.<br>Made to mean something.':'Names with character.<br>Stories worth telling.<br>Words that stay with you.'}</p></div>
    ${!state.previewBefore?`<div class="proposal-site-addition ${highlight?'highlighted':''}">${highlight?`<span class="proposal-change-label">${icon('plus')}${casePage?'New case page':'New Case block'} · ${c.asset.alias}</span>`:''}<div class="proposal-site-case ${casePage?'case-page':''}"><div class="proposal-site-media"><img src="${c.asset.src}" alt="${c.asset.meta}">${c.asset.type==='video'?`<button class="proposal-film-play" data-asset="${c.asset.alias}" aria-label="Preview video2 poster">${icon('play')}</button>`:''}</div><div class="proposal-site-case-copy"><span class="proposal-site-kicker">${casePage?'The project':'Selected project / Sommerro'}</span><h3>${c.id==='naming'?'A little summer.<br>All year round.':'A new chapter.<br>A familiar feeling.'}</h3><p>${casePage?'A considered new identity for a place that brings people together.':'A place to come together.'}</p><span class="proposal-site-case-link">${casePage?'Identity · Naming · Art direction':'Explore the project'} ${icon('arrow')}</span></div></div></div>`:''}
    <div class="proposal-site-existing"><div class="proposal-site-existing-heading"><span>${casePage?'The details':'More of our work'}</span><span>Selected projects ↓</span></div><div class="proposal-site-grid"><div><img src="media/palette.svg" alt="Illustrative existing stationery project"><span>Everyday, considered.</span></div><div><img src="media/architecture.jpg" alt="Illustrative existing architecture project"><span>A different perspective.</span></div></div></div>
    <div class="proposal-site-footer"><strong>Let’s make something matter.</strong><span>hello@studio.example ↗</span></div>
  </div>`;
}

function openPagePreview(id) {
  state.previewEntry = changes.findIndex(c=>c.id===id);
  state.workspaceView = 'preview';
  state.previewBefore = false;
  history.replaceState(null, '', '#workspace-preview');
  render();
  document.querySelector(`[data-page-preview="${id}"]`)?.focus({preventScroll:true});
}

document.addEventListener('click', event => {
  const target = event.target.closest('button');
  if (!target) return;
  if (target.dataset.pagePreview) { openPagePreview(target.dataset.pagePreview); return; }
  const action = target.dataset.previewAction;
  if (!action) return;
  if (action === 'back') {
    state.workspaceView = 'changes';
    history.replaceState(null, '', '#workspace');
  }
  if (action === 'before') state.previewBefore = true;
  if (action === 'after') state.previewBefore = false;
  if (action === 'desktop' || action === 'mobile') state.previewDevice = action;
  render();
  const focusSelector = action === 'back'
    ? `[data-page-preview="${changes[state.previewEntry].id}"]`
    : `[data-preview-action="${action}"]`;
  document.querySelector(focusSelector)?.focus({preventScroll:true});
});

document.addEventListener('change', event => {
  if (!event.target.matches('[data-preview-highlight]')) return;
  state.previewHighlight = event.target.checked;
  render();
  document.querySelector('[data-preview-highlight]')?.focus({preventScroll:true});
});
