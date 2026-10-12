#!/bin/bash
set -euo pipefail
python3 - "$RELEASE_VERSION" "$RUNNER_TEMP/RELEASE-NOTES.md" <<'PY'
from pathlib import Path
import re
import sys

version, output = sys.argv[1:]
raw = Path("CHANGELOG.md").read_bytes()
text = raw.decode("utf-8")
version_pattern = re.compile(rf"(?<![0-9A-Za-z.])v?{re.escape(version)}(?![0-9A-Za-z.+-])")
date_pattern = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
heading_pattern = re.compile(r"^##[ \t]+")
fence_pattern = re.compile(r"^[ ]{0,3}(`{3,}|~{3,})")
def fence_marker(content):
    opening = fence_pattern.match(content)
    if opening and (opening.group(1)[0] == "~" or "`" not in content[opening.end():]):
        return opening.group(1)
    return None

def paragraph_tail(start):
    tail = text[start:]
    boundary = re.search(r"\n(?:[ \t]*\r?\n|[ ]{0,3}#{1,6}(?:[ \t]|$)|[ ]{0,3}<!--)", tail, re.M)
    if boundary:
        tail = tail[:boundary.start()]
    for candidate in re.finditer(r"\n([^\r\n]*)", tail):
        if fence_marker(candidate.group(1)):
            return tail[:candidate.start()]
    return tail

headings = []
offset = 0
fence = None
in_comment = False
inline_end = -1
for line in text.splitlines(keepends=True):
    content = line.rstrip("\r\n")
    if fence is not None:
        closing = re.match(rf"^[ ]{{0,3}}{re.escape(fence[0])}{{{fence[1]},}}[ \t]*$", content)
        if closing:
            fence = None
        offset += len(line)
        continue

    if not in_comment:
        opening = fence_marker(content)
        if opening:
            fence = (opening[0], len(opening))
            offset += len(line)
            continue
        if heading_pattern.match(content):
            headings.append((offset, offset + len(line), content))

    cursor = 0
    while cursor < len(content):
        if in_comment:
            closing = content.find("-->", cursor)
            if closing < 0:
                break
            in_comment = False
            cursor = closing + 3
        elif offset + cursor < inline_end:
            cursor = min(len(content), inline_end - offset)
        elif content[cursor] == "\\":
            cursor += 2
        elif content[cursor] == "`":
            marker = re.match(r"`+", content[cursor:]).group()
            tail_start = offset + cursor + len(marker)
            tail = paragraph_tail(tail_start)
            closing = re.search(r"(?<!`)" + marker + r"(?!`)", tail)
            if closing:
                inline_end = tail_start + closing.end()
            cursor += len(marker)
        elif content.startswith("<!--", cursor):
            block_start = cursor <= 3 and content[:cursor] == " " * cursor
            if content.startswith("<!--->", cursor):
                cursor += 6
            elif content.startswith("<!-->", cursor):
                cursor += 5
            elif block_start:
                in_comment = True
                cursor += 4
            else:
                tail_start = offset + cursor + 4
                closing = paragraph_tail(tail_start).find("-->")
                if closing >= 0:
                    inline_end = tail_start + closing + 3
                cursor += 4
        else:
            cursor += 1
    offset += len(line)

matches = [
    candidate
    for candidate in headings
    if version_pattern.search(candidate[2]) and date_pattern.search(candidate[2])
]
if len(matches) != 1:
    raise SystemExit(
        f"CHANGELOG.md needs exactly one dated level-two section for {version}; found {len(matches)}"
    )
match = matches[0]
end = next((candidate[0] for candidate in headings if candidate[0] > match[0]), len(text))
section = text[match[0]:end]
Path(output).write_bytes(section.encode("utf-8"))
PY

python3 - <<'PYDATE'
import datetime, pathlib, re
heading=pathlib.Path(__import__('os').environ['RUNNER_TEMP'],'RELEASE-NOTES.md').read_text().splitlines()[0]
datetime.date.fromisoformat(re.search(r'[0-9]{4}-[0-9]{2}-[0-9]{2}',heading)[0])
PYDATE

python3 - <<'PYVERSION'
import json, os, pathlib
p=pathlib.Path('package.json')
if p.exists():
    m=json.loads(p.read_text())
    if 'version' in m and m['version']!=os.environ['RELEASE_VERSION']: raise SystemExit('package.json version mismatch')
PYVERSION
for file in .release-version VERSION version.txt; do
  [[ ! -f "$file" ]] || [[ "$(tr -d '[:space:]' < "$file" | sed 's/^v//')" == "$RELEASE_VERSION" ]] || exit 1
done
echo "release-notes-artifact-name=source-notes-$RELEASE_VERSION-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" >> "$GITHUB_OUTPUT"

