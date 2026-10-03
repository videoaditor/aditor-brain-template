#!/usr/bin/env python3
"""
Build the editor handbook (the read site) from the vault.

Safe by construction: only pages carrying `audience: editors` are read; internal
pages never enter the output. Wikilinks/markdown-links to non-published pages are
de-linked. English is the single source; German is generated at build time via
the Anthropic API and cached under i18n/ (committed) so rebuilds are cheap and
deterministic. Output is self-contained with relative links, so it works at any
mount point (a localhost preview or a /handbook/ path on your own host).

Usage: build.py <output_dir> [vault_dir]
Env:   ANTHROPIC_API_KEY (for translating new/changed pages; absent -> DE falls
       back to the English text for those pages, with a warning).
       HANDBOOK_BRAND  (the name shown in the handbook title/header; default
       "Company Brain").
"""
import sys, re, os, json, hashlib, shutil, pathlib, html, urllib.request

try:
    import markdown
except ImportError:
    sys.exit("ERROR: python 'markdown' not installed (the build.sh wrapper sets up a venv).")

HERE = pathlib.Path(__file__).resolve().parent
VAULT = pathlib.Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else HERE.parent.parent
OUT = pathlib.Path(sys.argv[1]).resolve()
CACHE = HERE / "i18n"

# The name shown in the handbook title and header. Each brain sets its own.
BRAND = os.environ.get("HANDBOOK_BRAND", "Company Brain").strip() or "Company Brain"
BRAND_INITIAL = BRAND[0].upper()

# Copy-protection assets are read once and INLINED into every page (not linked),
# so the deterrence applies even when a page is opened directly from disk. This
# is the friction half only; the per-viewer watermark lives in the auth gate.
PROTECT_CSS = (HERE / "assets" / "protect.css").read_text(encoding="utf-8")
PROTECT_JS = (HERE / "assets" / "protect.js").read_text(encoding="utf-8")

LANGS = ["en", "de"]
DEFAULT_LANG = "en"
AUD_RE = re.compile(r'^audience:\s*editors(\s|$)', re.M)
SECTION_ORDER = ["sop", "brands", "tools", "people", "meetings", "concepts"]

UI = {
    "en": {
        "search": "Search the handbook...", "updated": "Last updated", "home": "Home",
        "eyebrow": "Editor handbook", "h1": "How we make the work.",
        "lede": "Your SOPs, per-brand editing guides and the tools you use - one place, always current.",
        "no_match": "No matches",
        "sec": {"sop": "SOPs", "brands": "Brands", "tools": "Tools", "people": "Team", "meetings": "Pep Talks", "concepts": "Concepts"},
    },
    "de": {
        "search": "Handbuch durchsuchen...", "updated": "Zuletzt aktualisiert", "home": "Start",
        "eyebrow": "Editor-Handbuch", "h1": "Wie wir die Arbeit machen.",
        "lede": "Deine Anleitungen, Marken-Guides und die Tools, die du nutzt - an einem Ort, immer aktuell.",
        "no_match": "Keine Treffer",
        "sec": {"sop": "Anleitungen", "brands": "Marken", "tools": "Tools", "people": "Team", "meetings": "Pep Talks", "concepts": "Konzepte"},
    },
}
LANG_NAME = {"de": "German"}

TRANSLATE_PROMPT = """Translate the TITLE, SUMMARY and BODY below from English to {lang_name}.
This is operational handbook content for video editors (SOPs, per-brand guides, billing) - translate precisely and naturally, in the informal "du" form.

Rules:
- Keep all Markdown structure exactly (headings, lists, tables, bold, code fences, blockquotes).
- Do NOT translate: code, URLs, `inline code`, [[wikilink targets]] (keep the text inside [[...]] exactly), brand/product names, file names, emoji/labels, and currency amounts.
- Keep the three markers <<<TITLE>>>, <<<SUMMARY>>>, <<<BODY>>> exactly and in the same order.
- Output ONLY the three marked sections with the translated content, nothing else.

<<<TITLE>>>
{title}
<<<SUMMARY>>>
{summary}
<<<BODY>>>
{body}
"""


# ---------- parsing --------------------------------------------------------
def parse_front(text):
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---", 4)
    if end == -1:
        return {}, text
    block, body = text[4:end], text[end + 4:].lstrip("\n")
    meta = {}
    for line in block.splitlines():
        m = re.match(r'^([A-Za-z_]+):\s*(.*)$', line)
        if m:
            meta[m.group(1)] = m.group(2).strip()
    return meta, body


def discover():
    pages = []
    for f in sorted((VAULT / "wiki").rglob("*.md")):
        if f.name.startswith("_"):
            continue
        raw = f.read_text(encoding="utf-8")
        if not AUD_RE.search(raw):
            continue
        meta, body = parse_front(raw)
        pages.append({
            "section": f.parent.name, "slug": f.stem,
            "title": meta.get("title") or f.stem, "summary": meta.get("summary", ""),
            "updated": meta.get("updated", ""), "body": body,
            "url": f"{f.parent.name}/{f.stem}.html",
        })
    return pages


# ---------- translation (cached) -------------------------------------------
def _call_anthropic(api_key, prompt):
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps({"model": "claude-sonnet-5", "max_tokens": 8000,
                         "messages": [{"role": "user", "content": prompt}]}).encode("utf-8"),
        headers={"x-api-key": api_key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        d = json.load(r)
    return "".join(b.get("text", "") for b in d.get("content", []) if b.get("type") == "text")


def _parse_delims(out):
    m = re.search(r'<<<TITLE>>>\s*(.*?)\s*<<<SUMMARY>>>\s*(.*?)\s*<<<BODY>>>\s*(.*)$', out, re.S)
    if not m:
        raise ValueError("translation did not keep the markers")
    return m.group(1).strip(), m.group(2).strip(), m.group(3).strip()


def translate_page(lang, p):
    if lang == DEFAULT_LANG:
        return p["title"], p["summary"], p["body"]
    key = hashlib.sha256(("\x00".join([p["title"], p["summary"], p["body"]])).encode("utf-8")).hexdigest()
    cdir = CACHE / lang
    cdir.mkdir(parents=True, exist_ok=True)
    cf = cdir / f"{key}.json"
    if cf.exists():
        d = json.loads(cf.read_text(encoding="utf-8"))
        return d["title"], d["summary"], d["body"]
    api = os.environ.get("ANTHROPIC_API_KEY")
    if not api:
        print(f"  [i18n] no ANTHROPIC_API_KEY - '{p['slug']}' shows English under /{lang}")
        return p["title"], p["summary"], p["body"]
    prompt = TRANSLATE_PROMPT.format(lang_name=LANG_NAME.get(lang, lang), title=p["title"], summary=p["summary"], body=p["body"])
    try:
        t, s, b = _parse_delims(_call_anthropic(api, prompt))
        cf.write_text(json.dumps({"title": t, "summary": s, "body": b}, ensure_ascii=False), encoding="utf-8")
        print(f"  [i18n] translated '{p['slug']}' -> {lang}")
        return t, s, b
    except Exception as e:
        print(f"  [i18n] translate failed for '{p['slug']}' ({e}) - English fallback")
        return p["title"], p["summary"], p["body"]


# ---------- rendering ------------------------------------------------------
MD_EXT = ["tables", "fenced_code", "sane_lists"]
BAD_LINK = re.compile(r'<a\b[^>]*href="(?:[^"]*\.md(?:#[^"]*)?|(?:\.\./){2,}[^"]*)"[^>]*>(.*?)</a>', re.S)
URL_RE = re.compile(r'(?<![\w<\[("])(https?://[^\s<>()\]]+)')
# Author opt-out: a fenced block tagged ```copyable renders through python-
# markdown's fenced_code as <pre><code class="language-copyable">...</code></pre>.
# We post-process that into a .copyable container (exempt from the copy-
# protection CSS/JS) with a small Copy button. A regex over the already-rendered
# HTML is the simplest robust hook into the existing pipeline. Default (no
# ```copyable fence) stays non-copyable.
COPYABLE_RE = re.compile(r'<pre><code class="(?:language-)?copyable">(.*?)</code></pre>', re.S)


def mark_copyable(rendered):
    def repl(m):
        return ('<div class="copyable">'
                '<button class="copy-btn" type="button">Copy</button>'
                f'<pre><code>{m.group(1)}</code></pre></div>')
    return COPYABLE_RE.sub(repl, rendered)


def resolve_wikilinks(body, slugmap, to_lang):
    def repl(m):
        inner = m.group(1).strip()
        target, alias = (inner.split("|", 1) + [None])[:2]
        page = target.split("#", 1)[0].strip()
        base = page.split("/")[-1]
        text = alias.strip() if alias else base
        if base in slugmap:
            return f"[{text}]({to_lang}{slugmap[base]})"
        return text
    return re.sub(r'\[\[([^\]]+)\]\]', repl, body)


def render_md(body):
    body = URL_RE.sub(r'<\1>', body)
    return mark_copyable(BAD_LINK.sub(r'\1', markdown.markdown(body, extensions=MD_EXT)))


def nav_html(pages, ui, to_lang, current_url=None):
    by_sec = {}
    for p in pages:
        by_sec.setdefault(p["section"], []).append(p)
    out = ['<nav class="side">']
    for s in [x for x in SECTION_ORDER if x in by_sec] + [x for x in by_sec if x not in SECTION_ORDER]:
        out.append(f'<div class="nav-sec">{html.escape(ui["sec"].get(s, s.title()))}</div><ul>')
        for p in sorted(by_sec[s], key=lambda x: x["title"].lower()):
            cls = ' class="on"' if p["url"] == current_url else ""
            out.append(f'<li{cls}><a href="{to_lang}{p["url"]}">{html.escape(p["title"])}</a></li>')
        out.append("</ul>")
    out.append("</nav>")
    return "\n".join(out)


def switcher(to_root, lang, page_url):
    out = ['<div class="langsw">']
    for L in LANGS:
        target = f'{to_root}{L}/{page_url if page_url else "index.html"}'
        out.append(f'<a class="lang{" on" if L == lang else ""}" href="{target}">{L.upper()}</a>')
    out.append("</div>")
    return "".join(out)


def shell(title, lang, to_root, to_lang, ui, nav, main, sw):
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<title>{html.escape(title)} - {html.escape(BRAND)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Hanken+Grotesk:wght@400;500;600;700;800&family=IBM+Plex+Mono:wght@400;500&display=swap">
<link rel="stylesheet" href="{to_root}assets/handbook.css">
<style>{PROTECT_CSS}</style>
</head>
<body>
<header class="topbar">
  <button class="menu" aria-label="Menu">&#9776;</button>
  <a class="mark" href="{to_lang}index.html"><span class="a">{html.escape(BRAND_INITIAL)}</span> {html.escape(BRAND)}</a>
  {sw}
  <div class="search"><input id="q" type="search" placeholder="{html.escape(ui['search'])}" autocomplete="off"><div id="results"></div></div>
</header>
<div class="layout">
  {nav}
  <main class="content">
  {main}
  </main>
</div>
<div class="scrim"></div>
<script>window.__BASE__="{to_lang}";window.__LANG__="{lang}";</script>
<script src="{to_root}assets/handbook.js"></script>
<script>{PROTECT_JS}</script>
</body>
</html>
"""


def build_lang(lang, pages_src, slugmap):
    ui = UI[lang]
    tpages = []
    for p in pages_src:
        t, s, b = translate_page(lang, p)
        tpages.append({**p, "title": t, "summary": s, "body": b})

    langdir = OUT / lang
    # content pages: /<lang>/<section>/<slug>.html  (to_lang="../", to_root="../../")
    for p in tpages:
        to_lang, to_root = "../", "../../"
        body = resolve_wikilinks(p["body"], slugmap, to_lang)
        main = (f'<article class="doc"><p class="crumb">{html.escape(ui["sec"].get(p["section"], p["section"].title()))}</p>'
                f'<h1>{html.escape(p["title"])}</h1>')
        if p["summary"]:
            main += f'<p class="lede">{html.escape(p["summary"])}</p>'
        main += render_md(body)
        if p["updated"]:
            main += f'<p class="updated">{html.escape(ui["updated"])} {html.escape(p["updated"])}</p>'
        main += "</article>"
        nav = nav_html(tpages, ui, to_lang, p["url"])
        f = langdir / p["section"] / f'{p["slug"]}.html'
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(shell(p["title"], lang, to_root, to_lang, ui, nav, main, switcher(to_root, lang, p["url"])), encoding="utf-8")

    # lang home: /<lang>/index.html  (to_lang="", to_root="../")
    by_sec = {}
    for p in tpages:
        by_sec.setdefault(p["section"], []).append(p)
    cards = []
    for s in [x for x in SECTION_ORDER if x in by_sec] + [x for x in by_sec if x not in SECTION_ORDER]:
        items = sorted(by_sec[s], key=lambda x: x["title"].lower())
        links = "".join(f'<li><a href="{p["url"]}">{html.escape(p["title"])}</a></li>' for p in items)
        cards.append(f'<section class="card"><h2>{html.escape(ui["sec"].get(s, s.title()))} <span>{len(items)}</span></h2><ul>{links}</ul></section>')
    home = (f'<div class="hero"><p class="eyebrow">{html.escape(ui["eyebrow"])}</p>'
            f'<h1>{html.escape(ui["h1"])}</h1><p class="lede">{html.escape(ui["lede"])}</p></div>'
            f'<div class="cards">{"".join(cards)}</div>')
    nav = nav_html(tpages, ui, "", None)
    (langdir / "index.html").write_text(shell(ui["home"], lang, "../", "", ui, nav, home, switcher("../", lang, None)), encoding="utf-8")

    # per-lang search index
    idx = [{"title": p["title"], "summary": p["summary"], "section": ui["sec"].get(p["section"], p["section"].title()),
            "url": p["url"], "text": re.sub(r'\s+', ' ', re.sub(r'[#*`>\[\]|_-]', ' ', p["body"]))[:1500]} for p in tpages]
    (langdir / "search-index.json").write_text(json.dumps(idx, ensure_ascii=False), encoding="utf-8")
    return len(tpages)


def build():
    pages = discover()
    slugmap = {p["slug"]: p["url"] for p in pages}
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "assets").mkdir(parents=True)
    for a in ("handbook.css", "handbook.js"):
        shutil.copy(HERE / "assets" / a, OUT / "assets" / a)

    n = 0
    for lang in LANGS:
        n = build_lang(lang, pages, slugmap)

    # root redirect to preferred/default language
    (OUT / "index.html").write_text(
        f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>{html.escape(BRAND)}</title><script>
try{{var l=localStorage.getItem('hb_lang');}}catch(e){{}}
if(l!=='en'&&l!=='de'){{l=(navigator.language||'en').toLowerCase().indexOf('de')===0?'de':'en';}}
location.replace(l+'/index.html');
</script></head><body><noscript><a href="{DEFAULT_LANG}/index.html">Enter</a></noscript></body></html>""",
        encoding="utf-8")

    print(f"built {n} pages x {len(LANGS)} languages -> {OUT}")


if __name__ == "__main__":
    build()
