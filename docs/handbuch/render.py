#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare the handbook articles for Outline (Git is the source, Outline only shows them).

  render.py list                         all articles in order: file, parent, title, Outline address, position
                                         under the parent (0-based, the index of move_document), Outline id,
                                         Outline id of the parent (the collection for a section)
  render.py render <file> [--allow-missing]
                                         the text for Outline: without header, links to other articles
                                         as Outline addresses; at the end a link to the next article (in the
                                         order of list, if it is published), the source file and Ko-fi
  render.py blocks <file> [<n>]          the bash blocks of an article (numbered), or only block n, to run them
                                         word by word in a test container or on the test VM
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO_URL = "https://code.bashclub.org/bashclub/zsync/src/branch/main/docs/handbuch/"
KOFI_URL = "https://ko-fi.com/A0A1J73JR"
# the Ko-fi button (kofi-button.py) from the repository: readers load nothing from ko-fi.com; Outline cannot link an
# image, so the address follows below it
KOFI_BUTTON = "https://code.bashclub.org/bashclub/zsync/raw/branch/main/docs/handbuch/kofi-block.png"
LINK = re.compile(r"\]\((?!https?://|#|mailto:)([^)#\s]+\.md)(#[^)\s]*)?\)")


def read(path):
    """header (dict) and text of an article"""
    with open(path, encoding="utf-8") as f:
        content = f.read()
    m = re.match(r"---\n(.*?)\n---\n", content, re.S)
    if not m:
        sys.exit(f"{path}: no header (--- title: … ---)")
    head = {}
    for line in m.group(1).splitlines():
        key, _, value = line.partition(":")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        head[key.strip()] = value
    if not head.get("title"):
        sys.exit(f"{path}: no title")
    return head, content[m.end():].lstrip("\n")


def articles():
    """(path, parent path or None) in the order of Outline"""
    result = []
    for section in sorted(d for d in os.listdir(ROOT) if re.match(r"\d+-", d) and os.path.isdir(os.path.join(ROOT, d))):
        index = os.path.join(ROOT, section, "_index.md")
        if not os.path.isfile(index):
            sys.exit(f"{section}: no _index.md")
        result.append((index, None))
        for name in sorted(n for n in os.listdir(os.path.join(ROOT, section)) if re.match(r"\d+-.*\.md$", n)):
            result.append((os.path.join(ROOT, section, name), index))
    return result


def rel(path):
    return os.path.relpath(path, ROOT)


BLOCK_START = re.compile(r"\s*([-*+] |\d+\. |\||#|:::|>|```|---$)")


def unwrap(text):
    """join the lines of a paragraph or list item wrapped in the source (Outline would keep the line breaks)"""
    out = []
    fence = False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            fence = not fence
            out.append(line)
            continue
        prev = out[-1] if out else ""
        # a line that is bold as a whole (a message in the reference) stays a paragraph of its own
        if not fence and line.strip() and re.fullmatch(r"\*\*.*\*\*", prev.strip()) and not BLOCK_START.match(line):
            out.append("")
            out.append(line)
        elif (not fence and line.strip() and prev.strip() and not BLOCK_START.match(line)
                and not re.match(r"\s*(\||#|:::|```|---$)", prev)):
            out[-1] = prev.rstrip() + " " + line.strip()
        else:
            out.append(line)
    return "\n".join(out)


def render(path, allow_missing):
    head, text = read(path)
    if re.match(r"# ", text):
        sys.exit(f"{rel(path)}: the text must not start with a heading of the first level, Outline shows the title")
    missing = []

    def link(m):
        target = os.path.normpath(os.path.join(os.path.dirname(path), m.group(1)))
        if not os.path.isfile(target):
            sys.exit(f"{rel(path)}: link to a missing file {m.group(1)}")
        url = read(target)[0].get("outline", "")
        if not url:
            missing.append(rel(target))
            return "]()"
        # anchors in Outline: h-<heading as in the source>
        anchor = "#h-" + m.group(2)[1:] if m.group(2) else ""
        return f"]({url}{anchor})"

    text = LINK.sub(link, unwrap(text))
    if missing and not allow_missing:
        sys.exit(f"{rel(path)}: links to articles that are not published yet: {', '.join(sorted(set(missing)))}")
    # links whose target is not published yet: only the text stays
    text = re.sub(r"\[([^\]]*)\]\(\)", r"\1", text)
    # the next article in the order of the handbook (the next section after the last article of a section)
    order = [p for p, _ in articles()]
    following = ""
    if path in order and order.index(path) + 1 < len(order):
        nxt = order[order.index(path) + 1]
        head_next = read(nxt)[0]
        if head_next.get("outline"):
            following = f"**Weiter:** [{head_next['title']}]({head_next['outline']})\n\n"
    # end of the page: the Ko-fi block (question and button in one picture, Outline centers it; no alt text, Outline
    # would show it as a caption), the next article, the note on the source
    kofi = f"![]({KOFI_BUTTON})\n\n[{KOFI_URL.removeprefix('https://')}]({KOFI_URL})\n\n"
    note = (f"---\n\n*Quelle dieser Seite: [{rel(path)}]({REPO_URL}{rel(path)}) im Repository von bashclub-zsync. "
            "Änderungen bitte dort, diese Seite wird daraus erzeugt.*\n")
    return text.rstrip("\n") + "\n\n" + kofi + following + note


def blocks(path):
    """the bash code blocks of an article"""
    return re.findall(r"^```bash\n(.*?)^```", read(path)[1], re.S | re.M)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "list":
        collection = read(os.path.join(ROOT, "_collection.md"))[0].get("outline_id") or "-"
        position, sections = {}, 0
        for path, parent in articles():
            head = read(path)[0]
            if parent:
                position[parent] = position.get(parent, -1) + 1
                index, parent_id = position[parent], read(parent)[0].get("outline_id") or "-"
            else:
                index, parent_id, sections = sections, collection, sections + 1
            print("\t".join([rel(path), rel(parent) if parent else "-", head["title"], head.get("outline") or "-",
                             str(index), head.get("outline_id") or "-", parent_id]))
    elif len(sys.argv) >= 3 and sys.argv[1] == "render":
        sys.stdout.write(render(os.path.abspath(sys.argv[2]), "--allow-missing" in sys.argv[3:]))
    elif len(sys.argv) >= 3 and sys.argv[1] == "blocks":
        found = blocks(os.path.abspath(sys.argv[2]))
        if len(sys.argv) >= 4:
            sys.stdout.write(found[int(sys.argv[3]) - 1])
        else:
            for n, block in enumerate(found, 1):
                print(f"### {n}\n{block}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
