#!/usr/bin/env bash
# ingest.sh: convert one requirement source to markdown for the BA.
#
# Usage:
#   ingest.sh <file|url> <slug> [--name NAME]
#
# Writes docs/requirements/<slug>/sources/<name>.md (repo root, main worktree) with a header
# recording origin, retrieval time and converter. Original files are copied to sources/raw/.
#   .md .markdown .txt          copied as is
#   .pdf                        pdftotext -layout; a scanned PDF (no text layer) is exported
#                               to sources/<name>-pages/*.png for the BA to read as images
#   .docx .pptx .xlsx           pandoc, else markitdown, else built-in fallback (python3)
#   .doc                        antiword or catdoc (or convert it to .docx first)
#   .png .jpg .jpeg .gif .webp  copied; a stub .md is written for the BA's description
#   GitHub issue/PR/discussion  read with gh (title, body, comments)
#   Google Docs link            exported as markdown when the document is public
#   other http(s) URL           fetched with curl, HTML converted to markdown
#
# Exit codes (no output file is created on failure, and never an empty one):
#   0 converted   2 usage error   3 missing tool (install hint printed)
#   4 login or permission required: ask the stakeholder for an exported file
#   5 scanned PDF: pages exported as images, the BA must read them
#   6 unreadable, empty, not found, or no readable text (e.g. JavaScript-only page)
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { local code="$1"; shift; echo "ingest: $*" >&2; exit "$code"; }
have() { command -v "$1" >/dev/null 2>&1; }

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '/^# Usage:/,/^[^#]/{/^[^#]/d;s/^# \{0,1\}//;p;}' "$0"; exit 0; }
[[ $# -ge 2 ]] || fail 2 "usage: ingest.sh <file|url> <slug> [--name NAME] (see --help)"
SRC="$1" SLUG="$2"; shift 2
NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in --name) NAME="${2:?--name needs a value}"; shift 2 ;; *) fail 2 "unknown option $1" ;; esac
done
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail 2 "slug must be lowercase letters, digits and dashes"

if common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then ROOT="$(dirname "$common")"
else ROOT="$PWD"; fi
OUT_DIR="$ROOT/docs/requirements/$SLUG/sources"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

sanitize() { tr '[:upper:]' '[:lower:]' <<<"$1" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-60; }

# finish <converter> <body-file> : write the final markdown with its header (never empty)
finish() {
  local conv="$1" body="$2"
  [[ -s "$body" ]] && grep -q '[^[:space:]]' "$body" || fail 6 "no readable text in $SRC"
  mkdir -p "$OUT_DIR"
  local out="$OUT_DIR/$NAME.md"
  {
    echo "---"
    echo "source: \"$SRC\""
    echo "retrieved: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "converter: $conv"
    echo "---"
    echo
    cat "$body"
  } > "$TMP/final.md"
  mv "$TMP/final.md" "$out"
  echo "$out"
}

keep_raw() { mkdir -p "$OUT_DIR/raw"; cp -f "$SRC" "$OUT_DIR/raw/"; }

office() { # office <kind> : pandoc > markitdown > fallback
  local kind="$1"
  if have pandoc && pandoc -f "$kind" -t gfm --wrap=none "$SRC" -o "$TMP/body.md" 2>/dev/null; then finish pandoc "$TMP/body.md"
  elif have markitdown && markitdown "$SRC" > "$TMP/body.md" 2>/dev/null; then finish markitdown "$TMP/body.md"
  else
    have python3 || fail 3 "need pandoc, markitdown or python3 to read .$kind (e.g. sudo apt install pandoc)"
    python3 -I "$HERE/ingest_fallback.py" "$kind" "$SRC" > "$TMP/body.md" || fail 6 "cannot read $SRC as .$kind"
    echo "ingest: used the built-in converter; install pandoc for better tables and formatting" >&2
    finish "squad-fallback ($kind)" "$TMP/body.md"
  fi
}

ingest_pdf() {
  have pdftotext || fail 3 "pdftotext missing: install poppler-utils (apt install poppler-utils / brew install poppler)"
  pdftotext -layout "$SRC" "$TMP/body.md" 2>/dev/null || fail 6 "cannot read PDF $SRC"
  local pages chars
  pages="$(pdfinfo "$SRC" 2>/dev/null | awk '/^Pages:/{print $2}')"; pages="${pages:-1}"
  chars="$(tr -d '[:space:]' < "$TMP/body.md" | wc -c)"
  if (( chars < 20 * pages )); then
    have pdftoppm || fail 3 "scanned PDF and pdftoppm missing: install poppler-utils"
    mkdir -p "$OUT_DIR/$NAME-pages"
    pdftoppm -png -r 110 "$SRC" "$OUT_DIR/$NAME-pages/page"
    {
      echo "# Scanned PDF: $(basename "$SRC")"
      echo
      echo "This PDF has no text layer. Its $pages page(s) were exported as images; the BA reads"
      echo "each image and writes the content below."
      echo
      for f in "$OUT_DIR/$NAME-pages"/*.png; do echo "- $NAME-pages/$(basename "$f")"; done
      echo
      echo "## Content (written by the BA from the page images)"
    } > "$TMP/stub.md"
    finish "pdftoppm (scanned)" "$TMP/stub.md" >/dev/null
    keep_raw
    fail 5 "scanned PDF: $pages page image(s) in $OUT_DIR/$NAME-pages; read them as images"
  fi
  keep_raw; finish "pdftotext -layout" "$TMP/body.md"
}

ingest_image() {
  mkdir -p "$OUT_DIR"; cp -f "$SRC" "$OUT_DIR/"
  printf '# Image: %s\n\n![%s](%s)\n\n## Description (written by the BA from the image)\n' \
    "$(basename "$SRC")" "$(basename "$SRC")" "$(basename "$SRC")" > "$TMP/stub.md"
  finish "image (described by the BA)" "$TMP/stub.md"
}

ingest_github() { # github.com/<o>/<r>/(issues|pull|discussions)/<n>
  have gh || fail 3 "gh is required for GitHub links"
  local o r kind n
  IFS=/ read -r o r kind n _ <<<"$(sed -E 's#^https?://github.com/##' <<<"$SRC")"
  n="${n%%[#?]*}"
  case "$kind" in
    issues|pull)
      local sub=issue; [[ "$kind" == pull ]] && sub=pr
      gh "$sub" view "$n" -R "$o/$r" --json title,body,comments,author,state \
        --jq '"# \(.title)\n\n_by @\(.author.login), \(.state)_\n\n\(.body)\n" + ([.comments[] | "\n## Comment by @\(.author.login)\n\n\(.body)\n"] | join(""))' \
        > "$TMP/body.md" 2>"$TMP/err" || { grep -qiE "could not resolve|not found|404" "$TMP/err" && fail 6 "GitHub item not found: $SRC"; fail 4 "cannot read $SRC with the current gh account: $(cat "$TMP/err")"; }
      ;;
    discussions)
      gh api graphql -F o="$o" -F r="$r" -F n="$n" -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){discussion(number:$n){title body author{login} comments(first:100){nodes{body author{login}}}}}}' \
        --jq '.data.repository.discussion | "# \(.title)\n\n_by @\(.author.login)_\n\n\(.body)\n" + ([.comments.nodes[] | "\n## Comment by @\(.author.login)\n\n\(.body)\n"] | join(""))' \
        > "$TMP/body.md" 2>"$TMP/err" || fail 4 "cannot read discussion $SRC: $(cat "$TMP/err")"
      ;;
    *) return 1 ;;
  esac
  finish "gh $kind" "$TMP/body.md"
}

fetch() { # fetch <url> <out> : prints "<http-code> <effective-url>"
  curl -sSL --max-time 30 -A "Mozilla/5.0 (squad ingest)" -o "$2" -w '%{http_code} %{url_effective}' "$1" 2>"$TMP/curl.err" \
    || fail 6 "cannot fetch $1: $(cat "$TMP/curl.err")"
}

login_wall() { # login_wall <code> <final-url> <file> : true if the response is a login page
  [[ "$1" =~ ^(401|403|407)$ ]] && return 0
  grep -qiE '(accounts\.google\.com|/login|/signin|/sign-in|/sso|/auth/|ServiceLogin|okta\.com|login\.microsoftonline)' <<<"$2" && return 0
  grep -qiE '<input[^>]+type=["'"'"']?password' "$3" && return 0
  return 1
}

ingest_url() {
  local url="$SRC" code final
  if [[ "$url" =~ ^https?://github\.com/[^/]+/[^/]+/(issues|pull|discussions)/[0-9]+ ]]; then ingest_github; return; fi
  if [[ "$url" =~ ^https?://docs\.google\.com/document/d/([A-Za-z0-9_-]+) ]]; then
    read -r code final <<<"$(fetch "https://docs.google.com/document/d/${BASH_REMATCH[1]}/export?format=md" "$TMP/body.md")"
    login_wall "$code" "$final" "$TMP/body.md" && fail 4 "Google Doc is not public: ask for an exported .docx/.pdf or 'Anyone with the link' access"
    [[ "$code" == 200 ]] || fail 6 "Google Docs export failed (HTTP $code)"
    finish "google docs export (md)" "$TMP/body.md"; return
  fi
  read -r code final <<<"$(fetch "$url" "$TMP/page.html")"
  login_wall "$code" "$final" "$TMP/page.html" && fail 4 "$url requires login (HTTP $code, landed on $final): ask for an exported file"
  [[ "$code" == 200 ]] || fail 6 "$url returned HTTP $code"
  if grep -qiE '^\s*<(!doctype html|html)' "$TMP/page.html"; then
    if have pandoc; then pandoc -f html -t gfm --wrap=none "$TMP/page.html" -o "$TMP/body.md" 2>/dev/null || fail 6 "cannot convert $url"
    else python3 -I "$HERE/ingest_fallback.py" html "$TMP/page.html" > "$TMP/body.md" || fail 6 "cannot convert $url"; fi
  else cp "$TMP/page.html" "$TMP/body.md"; fi
  (( $(tr -d '[:space:]' < "$TMP/body.md" | wc -c) >= 200 )) \
    || fail 6 "$url has almost no readable text (JavaScript-only page?): try WebFetch or ask for an export"
  finish "curl + $(have pandoc && echo pandoc || echo squad-fallback)" "$TMP/body.md"
}

if [[ "$SRC" =~ ^https?:// ]]; then
  have curl || fail 3 "curl is required for URLs"
  [[ -n "$NAME" ]] || NAME="$(sanitize "$(sed -E 's#^https?://(www\.)?##' <<<"$SRC")")"
  ingest_url; exit 0
fi

[[ -f "$SRC" ]] || fail 6 "file not found: $SRC"
[[ -s "$SRC" ]] || fail 6 "file is empty: $SRC"
base="$(basename "$SRC")"; ext="${base##*.}"; ext="${ext,,}"
[[ -n "$NAME" ]] || NAME="$(sanitize "${base%.*}")"
case "$ext" in
  md|markdown|txt) cp "$SRC" "$TMP/body.md"; keep_raw; finish copy "$TMP/body.md" ;;
  pdf) ingest_pdf ;;
  docx|pptx|xlsx) keep_raw; office "$ext" ;;
  doc)
    if have antiword; then antiword "$SRC" > "$TMP/body.md" || fail 6 "antiword failed"; keep_raw; finish antiword "$TMP/body.md"
    elif have catdoc; then catdoc "$SRC" > "$TMP/body.md" || fail 6 "catdoc failed"; keep_raw; finish catdoc "$TMP/body.md"
    else fail 3 ".doc needs antiword or catdoc (apt install antiword), or save it as .docx first"; fi ;;
  png|jpg|jpeg|gif|webp) ingest_image ;;
  *) fail 6 "unsupported file type .$ext (supported: md txt pdf docx pptx xlsx doc png jpg gif webp, or a URL)" ;;
esac
