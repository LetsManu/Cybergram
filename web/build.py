#!/usr/bin/env python3
"""Builds the static Cybergram website (W20-WEB) from the repo files.

    python3 web/build.py [--repo .] [--out web/dist]

Standard library only, so it runs in a bare python:alpine build stage.
- Pages: web/pages/*.html are body fragments; each starts with
  <!-- title: ... --> and <!-- description: ... --> lines and is wrapped
  in the shared layout (header, footer).
- Patch notes: rendered from launcher/assets/notes/*.md (the notes the
  launcher shows), newest first.
- Heroes: from assets/data/heroes/*.tres (+ skills, weapons), roles from
  src/ui/menu/hero_showcase.gd, texts from assets/localization/hud.csv,
  portraits from assets/ui/portraits/.
- Static files: web/static/ (CSS, JS, icons), fonts from assets/fonts/
  (SIL OFL; licence files copied next to them).
No external URL is ever loaded by a page: fonts, images and scripts are
served from the site itself (privacy page, PRIVACY.md).
"""

from __future__ import annotations

import argparse
import csv
import html
import re
import shutil
from pathlib import Path

REPO_URL = "https://github.com/LetsManu/Cybergram"
NAV = [
    ("index.html", "Home"),
    ("heroes.html", "Heroes"),
    ("patch-notes.html", "Patch notes"),
    ("status.html", "Server status"),
    ("leaderboard.html", "Leaderboard"),
]
FOOTER_LINKS = [("impressum.html", "Impressum"), ("privacy.html", "Privacy")]
FONTS = [
    ("chakrapetch/ChakraPetch-SemiBold.ttf", "ChakraPetch-SemiBold.ttf"),
    ("chakrapetch/ChakraPetch-Bold.ttf", "ChakraPetch-Bold.ttf"),
    ("ibmplexsans/IBMPlexSans-Variable.ttf", "IBMPlexSans-Variable.ttf"),
    ("ibmplexmono/IBMPlexMono-Medium.ttf", "IBMPlexMono-Medium.ttf"),
]
SKILL_KEYS = ["Q", "E", "C", "G"]


# --- markdown (the small subset the release notes use) ------------------------

def inline(text: str) -> str:
    """Escapes `text` and renders `code`, **bold**, *em* and [links](url)."""
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for p in parts:
        if p.startswith("`") and p.endswith("`") and len(p) > 1:
            out.append("<code>%s</code>" % html.escape(p[1:-1]))
            continue
        s = html.escape(p, quote=False)
        s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: _link(m.group(1), m.group(2)), s)
        s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", s)
        s = re.sub(r"(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)", r"<em>\1</em>", s)
        out.append(s)
    return "".join(out)


def _link(label: str, url: str) -> str:
    url = html.unescape(url)
    if url.startswith(("http://", "https://")):
        href = url
    elif url.startswith("#"):
        href = url
    else:  # a repo-relative path: link to the file on GitHub
        href = "%s/blob/main/%s" % (REPO_URL, url.lstrip("./"))
    return '<a href="%s" rel="noopener">%s</a>' % (html.escape(href), label)


def markdown(md: str, heading_shift: int = 0) -> str:
    """Renders headings, paragraphs, nested lists, tables, quotes and fences."""
    lines = md.replace("\r\n", "\n").split("\n")
    out: list[str] = []
    para: list[str] = []
    stack: list[tuple[int, str]] = []  # (indent, "ul"/"ol") of open lists
    i = 0

    def flush_para() -> None:
        if para:
            out.append("<p>%s</p>" % inline(" ".join(x.strip() for x in para)))
            para.clear()

    def close_lists(to_indent: int = -1) -> None:
        while stack and stack[-1][0] > to_indent:
            out.append("</li></%s>" % stack.pop()[1])

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped.startswith("```"):
            flush_para()
            close_lists()
            code = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            out.append("<pre><code>%s</code></pre>" % html.escape("\n".join(code)))
            i += 1
            continue
        if not stripped:
            flush_para()
            # A blank line inside a list keeps the list open when it continues.
            nxt = next((l for l in lines[i + 1:] if l.strip()), "")
            if stack and not re.match(r"\s*([-*+]|\d+\.)\s", nxt) and not nxt.startswith(" "):
                close_lists()
            i += 1
            continue
        m = re.match(r"(#{1,6})\s+(.*)", stripped)
        if m and not line.startswith(" "):
            flush_para()
            close_lists()
            level = min(6, len(m.group(1)) + heading_shift)
            out.append("<h%d>%s</h%d>" % (level, inline(m.group(2)), level))
            i += 1
            continue
        if stripped.startswith("|") and i + 1 < len(lines) and re.match(r"\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            flush_para()
            close_lists()
            head = [c.strip() for c in stripped.strip("|").split("|")]
            rows = []
            i += 2
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            t = ['<div class="table-wrap"><table><thead><tr>']
            t += ["<th scope=\"col\">%s</th>" % inline(c) for c in head]
            t.append("</tr></thead><tbody>")
            for r in rows:
                t.append("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in r))
            t.append("</tbody></table></div>")
            out.append("".join(t))
            continue
        if stripped.startswith(">"):
            flush_para()
            close_lists()
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip()[1:].strip())
                i += 1
            out.append("<blockquote>%s</blockquote>" % markdown("\n".join(quote)))
            continue
        m = re.match(r"(\s*)([-*+]|\d+\.)\s+(.*)", line)
        if m:
            flush_para()
            indent = len(m.group(1).replace("\t", "  "))
            kind = "ol" if m.group(2)[0].isdigit() else "ul"
            if stack and indent > stack[-1][0]:
                out.append("<%s>" % kind)
                stack.append((indent, kind))
            else:
                close_lists(indent)
                if stack and stack[-1][0] == indent:
                    out.append("</li>")
                else:
                    out.append("<%s>" % kind)
                    stack.append((indent, kind))
            item = [m.group(3)]
            i += 1
            # Continuation lines (indented, not a new item).
            while i < len(lines) and lines[i].strip() and lines[i].startswith(" ") \
                    and not re.match(r"\s*([-*+]|\d+\.)\s", lines[i]):
                item.append(lines[i].strip())
                i += 1
            out.append("<li>%s" % inline(" ".join(item)))
            continue
        if stack and line.startswith(" "):
            out.append(" " + inline(stripped))  # a paragraph inside a list item
            i += 1
            continue
        close_lists()
        para.append(line)
        i += 1
    flush_para()
    close_lists()
    return "\n".join(out)


# --- repo data ------------------------------------------------------------------

def version_key(name: str) -> tuple:
    nums = re.findall(r"\d+", name)
    return tuple(int(n) for n in nums[:3])


def load_strings(repo: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    with open(repo / "assets/localization/hud.csv", newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if len(row) >= 2:
                out[row[0]] = row[1]
    return out


def parse_tres(path: Path) -> tuple[dict[str, str], dict[str, str]]:
    """({ext id: res path}, {key: raw value}) of the [resource] section."""
    ext: dict[str, str] = {}
    props: dict[str, str] = {}
    section = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            section = line
            m = re.match(r'\[ext_resource .*path="([^"]+)".*id="([^"]+)"', line)
            if m:
                ext[m.group(2)] = m.group(1)
            continue
        if section.startswith("[resource]"):
            m = re.match(r"(\w+)\s*=\s*(.*)", line)
            if m:
                props[m.group(1)] = m.group(2).strip()
    return ext, props


def _str(v: str) -> str:
    v = v.strip()
    if v.startswith("&"):
        v = v[1:]
    return v.strip('"')


def res_file(repo: Path, res_path: str) -> Path:
    return repo / res_path.replace("res://", "")


def load_heroes(repo: Path, strings: dict[str, str]) -> list[dict]:
    showcase = (repo / "src/ui/menu/hero_showcase.gd").read_text(encoding="utf-8")
    block = re.search(r"const ROLE_KEYS := \{(.*?)\}", showcase, re.S)
    roles = dict(re.findall(r'"(\w+)":\s*"(\w+)"', block.group(1))) if block else {}
    heroes = []
    for stem, role_key in roles.items():
        path = repo / ("assets/data/heroes/hero_%s.tres" % stem)
        if not path.exists():
            continue
        ext, p = parse_tres(path)
        weapon = ""
        wm = re.search(r'ExtResource\("([^"]+)"\)', p.get("weapon", ""))
        if wm and wm.group(1) in ext:
            _, wp = parse_tres(res_file(repo, ext[wm.group(1)]))
            weapon = _str(wp.get("display_name", ""))
        skills = []
        for n, sid in enumerate(re.findall(r'ExtResource\("([^"]+)"\)', p.get("skills", "").split("(", 1)[-1])):
            if sid not in ext or "skills/" not in ext[sid]:
                continue
            _, sp = parse_tres(res_file(repo, ext[sid]))
            skid = _str(sp.get("id", ""))
            key = "HUD_SKILL_" + skid.replace("skill_", "", 1).upper()
            skills.append({"name": _str(sp.get("display_name", skid)), "text": strings.get(key, ""),
                           "ultimate": sp.get("ultimate", "false") == "true",
                           "key": SKILL_KEYS[len(skills)] if len(skills) < len(SKILL_KEYS) else ""})
        heroes.append({
            "stem": stem, "name": _str(p.get("display_name", stem)),
            "role": strings.get(role_key, role_key),
            "role_short": strings.get(role_key.replace("HUD_ROLE_", "HUD_ROLE_SHORT_"), ""),
            "line": strings.get("HUD_HERO_LINE_" + stem.upper(), ""),
            "hp": p.get("max_hp", ""), "speed": p.get("move_speed", ""),
            "armor": p.get("armor", "0.0"), "weapon": weapon, "skills": skills,
        })
    return heroes


# --- layout --------------------------------------------------------------------

LAYOUT = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta name="referrer" content="no-referrer">
<meta name="color-scheme" content="dark">
<link rel="icon" href="/static/icon.svg" type="image/svg+xml">
<link rel="stylesheet" href="/static/site.css">
<script src="/static/site.js" defer></script>
</head>
<body class="page-{slug}">
<a class="skip" href="#main">Skip to content</a>
<header class="top">
  <div class="wrap top-in">
    <a class="brand" href="/" aria-label="Cybergram home"><span class="brand-mark" aria-hidden="true"></span>CYBERGRAM</a>
    <nav aria-label="Main">
      <ul class="nav">{nav}</ul>
    </nav>
  </div>
</header>
<main id="main" class="wrap">
{body}
</main>
<footer class="foot">
  <div class="wrap foot-in">
    <p>Cybergram is a pre-alpha PvP first-person MOBA shooter. This site sets no cookies and loads nothing from other servers.</p>
    <ul class="foot-links">{footer}<li><a href="{repo}" rel="noopener">Source on GitHub</a></li></ul>
  </div>
</footer>
</body>
</html>
"""


def page(slug: str, file: str, title: str, description: str, body: str) -> str:
    nav = "".join('<li><a href="/%s"%s>%s</a></li>' % (
        f if f != "index.html" else "", ' aria-current="page"' if f == file else "", label) for f, label in NAV)
    footer = "".join('<li><a href="/%s"%s>%s</a></li>' % (
        f, ' aria-current="page"' if f == file else "", label) for f, label in FOOTER_LINKS)
    full_title = "Cybergram" if slug == "index" else "%s · Cybergram" % title
    return LAYOUT.format(title=html.escape(full_title), description=html.escape(description), slug=slug,
                         nav=nav, footer=footer, body=body, repo=REPO_URL)


def fragment(path: Path) -> tuple[str, str, str]:
    text = path.read_text(encoding="utf-8")
    title = re.search(r"<!--\s*title:\s*(.*?)\s*-->", text)
    desc = re.search(r"<!--\s*description:\s*(.*?)\s*-->", text)
    body = re.sub(r"<!--\s*(title|description):.*?-->\n?", "", text)
    return (title.group(1) if title else path.stem), (desc.group(1) if desc else ""), body


# --- generated pages --------------------------------------------------------------

def notes_body(repo: Path) -> str:
    notes_dir = repo / "launcher/assets/notes"
    files = sorted(notes_dir.glob("v*.md"), key=lambda p: version_key(p.stem), reverse=True)
    toc = []
    arts = []
    for n, f in enumerate(files):
        md = f.read_text(encoding="utf-8")
        first = md.lstrip().split("\n", 1)
        title = first[0].lstrip("# ").strip() if first[0].startswith("#") else f.stem
        rest = first[1] if len(first) > 1 and first[0].startswith("#") else md
        anchor = f.stem.replace(".", "-")
        toc.append('<li><a href="#%s">%s</a></li>' % (anchor, html.escape(f.stem)))
        content = markdown(rest, heading_shift=1)
        if n < 3:
            arts.append('<article class="note card" id="%s"><h2>%s</h2>%s</article>' % (
                anchor, inline(title), content))
        else:
            arts.append('<article class="note card" id="%s"><details><summary><h2>%s</h2></summary>%s'
                        '</details></article>' % (anchor, inline(title), content))
    return ('<section class="page-head"><p class="eyebrow">Releases</p><h1>Patch notes</h1>'
            '<p class="lede">The same notes the launcher shows, newest first. Older releases are folded; '
            'open them to read.</p></section>'
            '<nav class="toc card" aria-label="Releases"><ul>%s</ul></nav>%s') % ("".join(toc), "".join(arts))


def heroes_body(heroes: list[dict]) -> str:
    cards = []
    for h in heroes:
        skills = "".join(
            '<li class="skill%s"><span class="key" aria-hidden="true">%s</span><div><h4>%s%s</h4><p>%s</p></div></li>' % (
                " ult" if s["ultimate"] else "", html.escape(s["key"]), html.escape(s["name"]),
                ' <span class="tag">Ultimate</span>' if s["ultimate"] else "", html.escape(s["text"]))
            for s in h["skills"])
        stats = ('<dl class="stats"><div><dt>Health</dt><dd>%s</dd></div><div><dt>Speed</dt><dd>%s m/s</dd></div>'
                 '<div><dt>Weapon</dt><dd>%s</dd></div></dl>') % (
            html.escape(h["hp"]), html.escape(h["speed"]), html.escape(h["weapon"]))
        cards.append(
            '<article class="hero card" id="%s"><div class="hero-art"><img src="/img/heroes/%s.png" '
            'alt="%s, full-body portrait" width="720" height="1000" loading="lazy" decoding="async"></div>'
            '<div class="hero-text"><p class="eyebrow">%s</p><h2>%s</h2><p class="hero-line">%s</p>%s'
            '<h3 class="sr-only">Abilities</h3><ul class="skills">%s</ul></div></article>' % (
                h["stem"], h["stem"], html.escape(h["name"]), html.escape(h["role"]), html.escape(h["name"]),
                html.escape(h["line"]), stats, skills))
    jump = "".join('<li><a href="#%s">%s</a></li>' % (h["stem"], html.escape(h["name"])) for h in heroes)
    return ('<section class="page-head"><p class="eyebrow">Roster</p><h1>Heroes</h1>'
            '<p class="lede">%d heroes, each with a weapon and four abilities (default keys Q, E, C and G; '
            'G is the ultimate).</p></section><nav class="toc card" aria-label="Heroes"><ul>%s</ul></nav>%s') % (
        len(heroes), jump, "".join(cards))


# --- main ------------------------------------------------------------------------

def build(repo: Path, out: Path) -> None:
    web = repo / "web"
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(web / "static", out / "static")
    (out / "data").mkdir(parents=True)
    fonts = out / "static/fonts"
    fonts.mkdir(parents=True)
    for src, dst in FONTS:
        shutil.copy2(repo / "assets/fonts" / src, fonts / dst)
    for d in ["chakrapetch", "ibmplexsans"]:  # Plex Sans and Mono share the same OFL text
        shutil.copy2(repo / "assets/fonts" / d / "OFL.txt", fonts / ("OFL-%s.txt" % d))
    img = out / "img/heroes"
    img.mkdir(parents=True)
    strings = load_strings(repo)
    heroes = load_heroes(repo, strings)
    for h in heroes:
        shutil.copy2(repo / ("assets/ui/portraits/hero_%s.png" % h["stem"]), img / ("%s.png" % h["stem"]))
    pages = {}
    for f in sorted((web / "pages").glob("*.html")):
        title, desc, body = fragment(f)
        if f.name == "index.html":
            roster = "".join('<li><a href="/heroes.html#%s"><span class="thumb"><img src="/img/heroes/%s.png" alt="" '
                             'width="720" height="1000" decoding="async"></span><span>%s</span><small>%s</small></a></li>' % (
                                 h["stem"], h["stem"], html.escape(h["name"]), html.escape(h["role_short"]))
                             for h in heroes)
            body = body.replace("{{roster}}", roster)
        pages[f.name] = (f.stem, title, desc, body)
    pages["patch-notes.html"] = ("patch-notes", "Patch notes", "Cybergram release notes, newest first.",
                                 notes_body(repo))
    pages["heroes.html"] = ("heroes", "Heroes", "The Cybergram hero roster: roles, weapons and abilities.",
                            heroes_body(heroes))
    for name, (slug, title, desc, body) in pages.items():
        (out / name).write_text(page(slug, name, title, desc, body), encoding="utf-8")
    print("built %d pages, %d heroes into %s" % (len(pages), len(heroes), out))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    repo = Path(a.repo).resolve()
    build(repo, Path(a.out).resolve() if a.out else repo / "web/dist")
