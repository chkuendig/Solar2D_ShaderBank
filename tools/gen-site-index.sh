#!/bin/bash
# Write the landing page for the published site: every shader in the bank, grouped
# the way the viewer groups them, filterable by name, each one linking to its
# source file and to whoever it was ported from.
#
# The HTML5 build of the viewer itself is what you click through to from here; it
# is expected at <out-dir>/viewer/, produced by the Solar2D container.
#
# Usage: tools/gen-site-index.sh <out-dir> [project-root]
#   REPO_URL  base for source links (default: this repository on github.com)
#   REPO_REF  branch or commit the source links point at (default: main)
set -euo pipefail

OUT_DIR="${1:?usage: gen-site-index.sh <out-dir> [project-root]}"
ROOT="${2:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_URL="${REPO_URL:-https://github.com/${GITHUB_REPOSITORY:-chkuendig/Solar2D_ShaderBank}}"
REPO_REF="${REPO_REF:-main}"

cd "$ROOT"
mkdir -p "$OUT_DIR"

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# Readable title for a shader folder: _shader/ported/filter -> "Filter · ported"
folder_title() {
    local _rest="${1#_shader/}" _ported="" _name
    case "$_rest" in
        ported/*) _ported=" · ported"; _rest="${_rest#ported/}" ;;
    esac
    case "$_rest" in
        generator)    _name="Generator" ;;
        filter)       _name="Filter" ;;
        filter_trans) _name="Filter · transition" ;;
        composite)    _name="Composite" ;;
        *)            _name="$_rest" ;;
    esac
    printf '%s%s' "$_name" "$_ported"
}

total=$(find _shader -type f -name '*.lua' | wc -l)

{
cat <<HTML
<!DOCTYPE html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Solar2D ShaderBank</title>
<style>
  :root { color-scheme: dark; --bg:#12131a; --fg:#e7e7ee; --dim:#9a9ab0; --line:#2a2c3a; --accent:#7cc7ff; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }
  .wrap { max-width: 1000px; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
  h1 { font-size: 1.9rem; margin: 0 0 .35rem; letter-spacing: -.02em; }
  p.lede { color: var(--dim); margin: 0 0 1.5rem; max-width: 62ch; }
  a { color: var(--accent); }
  .cta { display:inline-block; background:var(--accent); color:#0c1017; font-weight:600; text-decoration:none;
         padding:.6rem 1.1rem; border-radius:8px; margin: 0 .5rem .5rem 0; }
  .cta.secondary { background:transparent; color:var(--fg); border:1px solid var(--line); }
  input[type=search] { width:100%; margin:1.75rem 0 .5rem; padding:.7rem .9rem; border-radius:8px;
         border:1px solid var(--line); background:#0d0e14; color:var(--fg); font-size:1rem; }
  .count { color:var(--dim); font-size:.85rem; }
  h2 { font-size:1rem; text-transform:uppercase; letter-spacing:.08em; color:var(--dim);
       margin:2rem 0 .5rem; padding-bottom:.4rem; border-bottom:1px solid var(--line); }
  ul { list-style:none; margin:0; padding:0; display:grid; gap:.15rem;
       grid-template-columns:repeat(auto-fill,minmax(310px,1fr)); }
  li { display:flex; align-items:baseline; gap:.5rem; padding:.35rem .5rem; border-radius:6px; }
  li:hover { background:#181a24; }
  li .name { font-weight:500; }
  li .group { font-size:.72rem; color:var(--dim); border:1px solid var(--line); border-radius:4px; padding:0 .35rem; }
  li .links { margin-left:auto; font-size:.8rem; white-space:nowrap; }
  section[hidden], li[hidden] { display:none; }
  footer { margin-top:3rem; color:var(--dim); font-size:.85rem; border-top:1px solid var(--line); padding-top:1rem; }
</style>
<div class="wrap">
<h1>Solar2D ShaderBank</h1>
<p class="lede">$total shaders for <a href="https://solar2d.com">Solar2D</a>, with the viewer that ships with them
built for the browser — pick a shader, swap the texture under it, drag the parameters around. Every shader keeps the
licence and credit of whoever wrote it first; the header of each <code>.lua</code> file says who that is.</p>
<p>
<a class="cta" href="viewer/">Open the shader viewer</a>
<a class="cta secondary" href="$REPO_URL">Source on GitHub</a>
</p>
<input type="search" id="q" placeholder="Filter $total shaders by name, group or category…" autocomplete="off">
<p class="count" id="count"></p>
HTML

find _shader -type d | LC_ALL=C sort | while read -r dir; do
    files=$(find "$dir" -maxdepth 1 -type f -name '*.lua' -printf '%f\n' | LC_ALL=C sort -f)
    [ -n "$files" ] || continue
    title=$(folder_title "$dir")
    printf '<section data-cat="%s">\n<h2>%s</h2>\n<ul>\n' "$(printf '%s' "$title" | esc)" "$(printf '%s' "$title" | esc)"
    while IFS= read -r f; do
        # kernel.name/kernel.group are what the viewer shows; the first URL in the
        # leading comment is the shader's origin, when it has one.
        meta=$(awk '
            /kernel\.group[ \t]*=/ && group=="" { if (match($0, /"[^"]*"/)) group=substr($0, RSTART+1, RLENGTH-2) }
            /kernel\.name[ \t]*=/  && name==""  { if (match($0, /"[^"]*"/)) name=substr($0, RSTART+1, RLENGTH-2) }
            url=="" { if (match($0, /https?:\/\/[^ \t")]+/)) url=substr($0, RSTART, RLENGTH) }
            FNR > 60 { exit }
            END { printf "%s\t%s\t%s", group, name, url }
        ' "$dir/$f")
        group=$(printf '%s' "$meta" | cut -f1 | esc)
        name=$(printf '%s' "$meta" | cut -f2 | esc)
        url=$(printf '%s' "$meta" | cut -f3 | esc)
        [ -n "$name" ] || name=$(printf '%s' "${f%.lua}" | esc)
        printf '<li data-q="%s"><span class="name">%s</span>' "$(printf '%s %s %s' "$name" "$group" "${f%.lua}" | tr 'A-Z' 'a-z' | esc)" "$name"
        [ -n "$group" ] && printf '<span class="group">%s</span>' "$group"
        printf '<span class="links"><a href="%s/blob/%s/%s/%s">source</a>' "$REPO_URL" "$REPO_REF" "$dir" "$f"
        [ -n "$url" ] && printf ' · <a href="%s">origin</a>' "$url"
        printf '</span></li>\n'
    done <<< "$files"
    printf '</ul>\n</section>\n'
done

cat <<HTML
<footer>
Built from <a href="$REPO_URL">$REPO_URL</a> by the
<a href="https://github.com/chkuendig/docker-solar2d">Solar2D Linux container</a>, which runs the HTML5 packager
that Solar2D otherwise only ships for macOS and Windows. Shaders are by their original authors — check the licence
in each file before using one.
</footer>
</div>
<script>
  const q = document.getElementById('q'), count = document.getElementById('count');
  const items = [...document.querySelectorAll('li[data-q]')];
  const sections = [...document.querySelectorAll('section')];
  const apply = () => {
    const term = q.value.trim().toLowerCase();
    let shown = 0;
    for (const li of items) {
      const hit = !term || li.dataset.q.includes(term) ||
                  li.closest('section').dataset.cat.toLowerCase().includes(term);
      li.hidden = !hit;
      if (hit) shown++;
    }
    for (const s of sections) s.hidden = !s.querySelector('li:not([hidden])');
    count.textContent = term ? shown + ' of ' + items.length + ' shaders' : '';
  };
  q.addEventListener('input', apply);
  apply();
</script>
HTML
} > "$OUT_DIR/index.html"

echo "wrote $OUT_DIR/index.html ($total shaders)"
