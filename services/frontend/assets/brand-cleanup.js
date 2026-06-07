/*
 * AmabileAI brand overlay for Opik UI — text + logo only.
 * Does NOT touch CSS/colors/layout. Only:
 *   - Replaces user-facing strings (Opik / Comet -> AmabileAI)
 *   - Swaps the upstream sidebar/header logo SVG for the AmabileAI logo image
 *   - Removes external comet.com / github.com/comet-ml / cometml social links
 *   - Pins document.title
 */
(function () {
  "use strict";

  var PRODUCT = "AmabileAI";
  var LOGO_URL = "/amabile/amabile-logo.png";
  var TITLE = "AmabileAI Observability";

  var STRING_MAP = [
    [/Comet\s*Opik/gi, PRODUCT],
    [/Opik\s*Cloud/gi, PRODUCT + " Cloud"],
    [/Opik\s*Playground/gi, PRODUCT + " Playground"],
    [/Opik\s*Optimizer/gi, PRODUCT + " Optimizer"],
    [/Opik\s*Guardrails/gi, PRODUCT + " Guardrails"],
    [/Opik\s*Agent\s*Optimizer/gi, PRODUCT + " Agent Optimizer"],
    [/Opik\s*LLM\s*Evaluation/gi, PRODUCT + " Evaluation"],
    [/Opik\s*Demo\s*Agent\s*Observability/gi, PRODUCT + " Demo"],
    [/Opik\s*Dashboard/gi, PRODUCT + " Dashboard"],
    [/Opik\s*Documentation/gi, PRODUCT + " Documentation"],
    [/Opik\s*Server/gi, PRODUCT + " Server"],
    [/Opik\s*Open\s*Source/gi, PRODUCT],
    [/Opik\s*Tracing/gi, PRODUCT + " Tracing"],
    [/Opik\s*SDK/gi, PRODUCT + " SDK"],
    [/Powered\s*by\s*Comet(\s*ML)?/gi, "Powered by " + PRODUCT],
    [/\(c\)\s*Comet\s*ML(,?\s*Inc\.?)?/gi, "© " + PRODUCT],
    [/©\s*Comet\s*ML(,?\s*Inc\.?)?/gi, "© " + PRODUCT],
    [/Comet\s*ML(,?\s*Inc\.?)?/gi, PRODUCT],
    [/Welcome\s*to\s*Opik/gi, "Welcome to " + PRODUCT],
    [/Try\s*Opik/gi, "Try " + PRODUCT],
    [/Comet\s*Account/gi, PRODUCT + " Account"],
    [/Comet\s*Workspace/gi, PRODUCT + " Workspace"],
    [/Star\s*us\s*on\s*GitHub/gi, ""],
    [/Join\s*our\s*Slack\s*community/gi, ""],
    [/Opik\s*documentation/gi, PRODUCT + " documentation"],
    [/Opik/g, PRODUCT],
    [/\bComet\b/g, PRODUCT],
  ];

  var EXTERNAL_HOST_RE = /(comet\.com|github\.com\/comet-ml|comet-ml\.github\.io|chat\.comet\.com|comet-ml\.slack\.com|x\.com\/Cometml|twitter\.com\/Cometml|linkedin\.com\/company\/comet-ml|youtube\.com\/@?Cometml|youtube\.com\/c\/Cometml)/i;

  function rewriteText(node) {
    var v = node.nodeValue;
    if (!v) return;
    var out = v;
    for (var i = 0; i < STRING_MAP.length; i++) {
      out = out.replace(STRING_MAP[i][0], STRING_MAP[i][1]);
    }
    if (out !== v) node.nodeValue = out;
  }

  function walkText(root) {
    if (!root) return;
    var w;
    try {
      w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    } catch (e) { return; }
    var n;
    while ((n = w.nextNode())) rewriteText(n);
  }

  function rewriteAttrs(root) {
    root = root || document;
    if (!root.querySelectorAll) return;
    var els = root.querySelectorAll('[aria-label],[title],[alt],[placeholder]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var attrs = ['aria-label', 'title', 'alt', 'placeholder'];
      for (var j = 0; j < attrs.length; j++) {
        var v = el.getAttribute(attrs[j]);
        if (!v) continue;
        var out = v;
        for (var k = 0; k < STRING_MAP.length; k++) {
          out = out.replace(STRING_MAP[k][0], STRING_MAP[k][1]);
        }
        if (out !== v) el.setAttribute(attrs[j], out);
      }
    }
  }

  function killExternalLinks(root) {
    root = root || document;
    var anchors = root.querySelectorAll ? root.querySelectorAll('a[href]') : [];
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      if (EXTERNAL_HOST_RE.test(a.getAttribute('href') || '')) {
        a.setAttribute('href', '#');
        a.setAttribute('aria-hidden', 'true');
        a.style.display = 'none';
      }
    }
  }

  /* ---- Logo replacement -------------------------------------------------
   * The upstream Opik UI renders its wordmark/leaf as inline <svg> or
   * <img> inside the sidebar header and login page. We find each candidate
   * and replace it with an <img src="/amabile/amabile-logo-180.png">.
   */
  function makeLogoImg(refEl) {
    var img = document.createElement('img');
    img.src = LOGO_URL;
    img.alt = PRODUCT;
    img.setAttribute('data-amabile-logo', '1');
    // Fixed visually-sensible logo dimensions; upstream slot often is 18px
    // (too small for AmabileAI wordmark to render readably).
    img.style.height = '28px';
    img.style.width = 'auto';
    img.style.maxWidth = '160px';
    img.style.objectFit = 'contain';
    img.style.display = 'inline-block';
    return img;
  }

  function mutateImgInPlace(imgEl) {
    if (imgEl.dataset && imgEl.dataset.amabileLogo) return;
    imgEl.setAttribute('src', LOGO_URL);
    imgEl.setAttribute('alt', PRODUCT);
    imgEl.setAttribute('data-amabile-logo', '1');
    // Override Tailwind h-[18px] etc. inline so the logo is readable.
    imgEl.style.setProperty('height', '28px', 'important');
    imgEl.style.setProperty('width', 'auto', 'important');
    imgEl.style.setProperty('max-width', '160px', 'important');
    imgEl.style.setProperty('object-fit', 'contain', 'important');
    imgEl.style.setProperty('object-position', 'left center', 'important');
  }

  var MAX_RETRY = 4;

  function isLogoCandidate(el) {
    if (!el) return false;
    if (el.dataset && el.dataset.amabileLogo) return false;
    // Retry budget for elements rejected once (e.g., 0×0 on first paint).
    var tries = el.getAttribute && parseInt(el.getAttribute('data-amabile-tries') || '0', 10) || 0;
    if (tries >= MAX_RETRY) return false;

    // Match by alt/src/aria-label/id/class/data-name containing opik|comet
    var hay = (
      (el.getAttribute && el.getAttribute('alt') || '') + ' ' +
      (el.getAttribute && el.getAttribute('src') || '') + ' ' +
      (el.getAttribute && el.getAttribute('aria-label') || '') + ' ' +
      (el.getAttribute && el.getAttribute('id') || '') + ' ' +
      (el.getAttribute && el.getAttribute('class') || '') + ' ' +
      (el.getAttribute && el.getAttribute('data-name') || '')
    ).toLowerCase();
    if (/opik|comet/.test(hay)) return true;

    // Inspect <use href|xlink:href> children — upstream uses SVG sprite
    // references like <use href="/assets/opik.svg#leaf"> which won't appear
    // in any attribute of the parent <svg>.
    if (el.querySelectorAll) {
      var uses = el.querySelectorAll('use');
      for (var i = 0; i < uses.length; i++) {
        var href = uses[i].getAttribute('href') || uses[i].getAttribute('xlink:href') || '';
        if (/opik|comet/i.test(href)) return true;
      }
    }

    // SVG inside <a href="/"> or sidebar/header/nav/aside — likely the
    // brand logo slot. Accept regardless of size (React may not have
    // laid out yet → getBoundingClientRect returns 0×0 on first paint).
    // Retry budget protects against runaway loops.
    if (el.tagName === 'SVG' || el.tagName === 'svg') {
      var p = el.closest && el.closest('a[href="/"], a[href="/home"], header, nav, aside');
      if (p) {
        var rect = el.getBoundingClientRect();
        // Accept if sized like a logo (60-240 × 16-64) OR not yet laid out (0×0)
        if ((rect.width === 0 && rect.height === 0) ||
            (rect.width >= 60 && rect.width <= 240 && rect.height >= 16 && rect.height <= 64)) {
          // Only treat as logo if it's the FIRST svg inside that wrapper
          // (avoids catching subsequent icons inside a nav).
          var firstSvg = p.querySelector('svg');
          if (firstSvg === el) return true;
        }
      }
    }

    // Bump retry counter on rejection so we eventually give up.
    if (el.setAttribute) el.setAttribute('data-amabile-tries', String(tries + 1));
    return false;
  }

  function replaceLogos(root) {
    root = root || document;
    if (!root.querySelectorAll) return;
    var els = root.querySelectorAll('img, svg');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (!isLogoCandidate(el)) continue;
      try {
        if (el.tagName === 'IMG') {
          // Mutate in place — preserve parent flex/grid layout & Tailwind classes.
          mutateImgInPlace(el);
        } else {
          // SVG: must replace (can't change tag to img otherwise).
          var img = makeLogoImg(el);
          el.parentNode && el.parentNode.replaceChild(img, el);
        }
      } catch (e) { /* ignore */ }
    }
  }

  function pinTitle() {
    if (document.title !== TITLE) document.title = TITLE;
  }

  function run(root) {
    walkText(root || document.body);
    rewriteAttrs(root);
    killExternalLinks(root);
    replaceLogos(root);
    pinTitle();
  }

  function boot() {
    pinTitle();
    if (document.body) run(document.body);

    var scheduled = false;
    var pendingNodes = [];
    function flush() {
      scheduled = false;
      var nodes = pendingNodes;
      pendingNodes = [];
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        if (n.nodeType === 3) rewriteText(n);
        else if (n.nodeType === 1) run(n);
      }
      pinTitle();
    }
    function schedule(n) {
      pendingNodes.push(n);
      if (scheduled) return;
      scheduled = true;
      (window.requestIdleCallback || window.requestAnimationFrame).call(window, flush);
    }

    var mo = new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var m = muts[i];
        if (m.target && m.target.nodeName === 'TITLE') continue;
        if (m.type === 'characterData') {
          rewriteText(m.target);
        } else if (m.type === 'childList') {
          m.addedNodes.forEach(schedule);
        } else if (m.type === 'attributes') {
          var t = m.target;
          if (t.tagName === 'A') {
            var h = t.getAttribute('href') || '';
            if (EXTERNAL_HOST_RE.test(h)) {
              t.setAttribute('href', '#');
              t.style.display = 'none';
            }
          }
          if (m.attributeName === 'aria-label' || m.attributeName === 'title' || m.attributeName === 'alt') {
            rewriteAttrs(t.parentNode || t);
          }
        }
      }
    });
    mo.observe(document.body || document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: true,
      attributeFilter: ['href', 'src', 'alt', 'aria-label', 'title']
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
