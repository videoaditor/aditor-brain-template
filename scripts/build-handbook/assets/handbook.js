(function () {
  var base = window.__BASE__ || "";

  // remember the chosen language for the root redirect
  try { if (window.__LANG__) localStorage.setItem("hb_lang", window.__LANG__); } catch (e) {}

  // close mobile nav when the scrim is tapped
  var scrim = document.querySelector(".scrim");
  if (scrim) scrim.addEventListener("click", function () { document.body.classList.remove("nav-open"); });

  // mobile nav
  var menu = document.querySelector(".menu");
  if (menu) {
    menu.addEventListener("click", function () { document.body.classList.toggle("nav-open"); });
    document.addEventListener("click", function (e) {
      if (document.body.classList.contains("nav-open") &&
          !e.target.closest(".side") && !e.target.closest(".menu")) {
        document.body.classList.remove("nav-open");
      }
    });
  }

  // search
  var q = document.getElementById("q");
  var box = document.getElementById("results");
  if (!q || !box) return;
  var idx = [], sel = -1, cur = [];

  fetch(base + "assets/search-index.json").then(function (r) { return r.json(); })
    .then(function (d) { idx = d; }).catch(function () {});

  function esc(s) { return (s || "").replace(/[&<>]/g, function (c) { return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]; }); }

  function run(term) {
    term = term.trim().toLowerCase();
    if (term.length < 2) { box.classList.remove("on"); box.innerHTML = ""; cur = []; return; }
    var toks = term.split(/\s+/);
    var hits = [];
    idx.forEach(function (p) {
      var hay = (p.title + " " + p.summary + " " + p.text + " " + p.section).toLowerCase();
      var score = 0, ok = true;
      toks.forEach(function (t) {
        if (hay.indexOf(t) === -1) ok = false;
        if (p.title.toLowerCase().indexOf(t) !== -1) score += 5;
        if (p.summary.toLowerCase().indexOf(t) !== -1) score += 2;
      });
      if (ok) hits.push({ p: p, s: score });
    });
    hits.sort(function (a, b) { return b.s - a.s; });
    cur = hits.slice(0, 8).map(function (h) { return h.p; });
    sel = -1;
    if (!cur.length) { box.innerHTML = '<div class="none">No matches</div>'; box.classList.add("on"); return; }
    box.innerHTML = cur.map(function (p) {
      return '<a href="' + base + p.url + '"><span class="r-sec">' + esc(p.section) +
        '</span><div class="r-ti">' + esc(p.title) + '</div><div class="r-su">' + esc(p.summary) + '</div></a>';
    }).join("");
    box.classList.add("on");
  }

  q.addEventListener("input", function () { run(q.value); });
  q.addEventListener("keydown", function (e) {
    var links = box.querySelectorAll("a");
    if (e.key === "ArrowDown") { e.preventDefault(); sel = Math.min(sel + 1, links.length - 1); }
    else if (e.key === "ArrowUp") { e.preventDefault(); sel = Math.max(sel - 1, 0); }
    else if (e.key === "Enter") { if (sel >= 0 && links[sel]) location.href = links[sel].href; return; }
    else if (e.key === "Escape") { box.classList.remove("on"); q.blur(); return; }
    else return;
    links.forEach(function (a, i) { a.classList.toggle("sel", i === sel); });
  });
  document.addEventListener("click", function (e) {
    if (!e.target.closest(".search")) box.classList.remove("on");
  });
})();
