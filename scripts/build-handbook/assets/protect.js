/* protect.js - build-time copy/paste deterrence for the editor handbook.
   Paired with protect.css, inlined into every page by build.py.

   HONESTY: this is DETERRENCE ONLY. It raises the cost of casual copy/paste,
   page-saving and printing, but it CANNOT stop screenshots, a phone photo of
   the screen, "view source"/devtools, or a reader who disables JavaScript. A per-viewer watermark is the real traceability layer (not shipped in this
   template); this file is only the friction half. Pure vanilla JS, no dependencies.

   Everything no-ops gracefully if the expected elements are absent. Anything
   inside an author-marked .copyable block (or a form field like the search box)
   is exempt from every block below. */
(function () {
  var content = document.querySelector(".content");
  var side = document.querySelector(".side");
  // The protected reading surfaces. The search box lives in the top bar, so it
  // is never one of these and is additionally exempted via exempt() below.
  var roots = [content, side].filter(Boolean);

  var NOTICE = "This handbook is not copyable. Ask in Slack if you need a link.";

  // Exempt: author-marked .copyable blocks (and descendants) and form fields.
  function exempt(target) {
    return !!(target && target.closest && target.closest(".copyable, input, textarea"));
  }

  // True when the event originates inside a protected reading surface.
  function inProtected(target) {
    if (!target) return false;
    for (var i = 0; i < roots.length; i++) {
      if (roots[i].contains && roots[i].contains(target)) return true;
    }
    return false;
  }

  if (roots.length) {
    // Block cut/contextmenu/dragstart/selectstart inside the reading surfaces.
    ["cut", "contextmenu", "dragstart", "selectstart"].forEach(function (evt) {
      document.addEventListener(evt, function (e) {
        if (exempt(e.target) || !inProtected(e.target)) return;
        e.preventDefault();
      }, true);
    });

    // Copy: block it, and overwrite the clipboard with a short notice.
    document.addEventListener("copy", function (e) {
      if (exempt(e.target) || !inProtected(e.target)) return;
      e.preventDefault();
      try {
        if (e.clipboardData) e.clipboardData.setData("text/plain", NOTICE);
      } catch (err) {}
    }, true);
  }

  // Swallow the save/print/view-source/copy/cut keyboard shortcuts. This is
  // bound at the document level on purpose: Cmd/Ctrl+S, +P and +U are page-wide
  // browser actions that fire with no element focused, so scoping them to the
  // content element would make them unreachable. We still NEVER touch Cmd/Ctrl+F
  // (find) and never fire inside the search box or a .copyable block.
  var BLOCKED_KEYS = { c: 1, x: 1, s: 1, p: 1, u: 1 };
  document.addEventListener("keydown", function (e) {
    if (!(e.metaKey || e.ctrlKey)) return;
    var k = (e.key || "").toLowerCase();
    if (!BLOCKED_KEYS[k]) return;   // f (find) and everything else pass through
    if (exempt(e.target)) return;   // search box / inputs / copyable stay live
    e.preventDefault();
  }, true);

  // Blank the reading surfaces while printing, then restore them. The CSS
  // @media print rule hides <body> too; this mirror covers print-to-PDF timing.
  var stash = [];
  window.addEventListener("beforeprint", function () {
    stash = [];
    roots.forEach(function (el) {
      stash.push([el, el.style.display]);
      el.style.display = "none";
    });
  });
  window.addEventListener("afterprint", function () {
    stash.forEach(function (pair) { pair[0].style.display = pair[1]; });
    stash = [];
  });

  // Wire the Copy buttons on author-marked .copyable blocks.
  var btns = document.querySelectorAll(".copyable .copy-btn");
  Array.prototype.forEach.call(btns, function (btn) {
    btn.addEventListener("click", function () {
      var wrap = btn.closest(".copyable");
      var pre = wrap && wrap.querySelector("pre");
      if (!pre) return;
      var text = pre.innerText;
      var flash = function () {
        var prev = btn.textContent;
        btn.textContent = "Copied";
        setTimeout(function () { btn.textContent = prev; }, 1500);
      };
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(flash, function () {});
        } else {
          var sel = window.getSelection();
          var range = document.createRange();
          range.selectNodeContents(pre);
          sel.removeAllRanges();
          sel.addRange(range);
          document.execCommand("copy");
          sel.removeAllRanges();
          flash();
        }
      } catch (err) {}
    });
  });
})();
