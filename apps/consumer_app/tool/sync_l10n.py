#!/usr/bin/env python3
"""Regenerate the committed localizations catalog from the ARB sources.

The Flutter SDK is not available in this environment, so `flutter gen-l10n`
cannot run here. This script reproduces the subset of gen-l10n output that the
repo commits: abstract accessors in app_localizations.dart and concrete
overrides in app_localizations_{en,am,om}.dart, driven by the ARB files in
lib/l10n (template: app_en.arb). It only ADDS members that are missing from
the committed catalog; existing members are left untouched so a future
`flutter gen-l10n` run stays byte-compatible for them.

Usage (from apps/consumer_app):  python3 tool/sync_l10n.py
"""

import json
import re
import sys
from pathlib import Path

ARB_KEYS = ("en", "am", "om")


def read_arb(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def placeholders(template: str) -> list[str]:
    seen, out = set(), []
    for m in re.finditer(r"\{(\w+)\}", template):
        if m.group(1) not in seen:
            seen.add(m.group(1))
            out.append(m.group(1))
    return out


def param_list(placeholders_: list[str], meta: dict | None) -> str:
    declared = (meta or {}).get("placeholders", {})
    parts = []
    for p in placeholders_:
        t = declared.get(p, {}).get("type", "String")
        parts.append(f"{t} {p}" if t in ("int", "num", "double") else f"String {p}")
    return ", ".join(parts)


def escape_literal(chunk: str) -> str:
    return chunk.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")


def dart_expression(template: str) -> str:
    """Return Dart source for an ARB message.

    gen-l10n compiles ICU plural messages into Intl.plural() calls (which
    requires importing package:intl) and everything else into interpolated
    string literals. The committed catalog predates this tool's existence
    and uses plain Dart interpolation for placeholder messages with no
    Intl import anywhere, so plural messages are compiled down to the
    equivalent conditional expression instead of Intl.plural(). That keeps
    the generated files byte-compatible in style with the rest of the
    catalog and free of a new dependency.
    """
    start = template.find(", plural,")
    if template.startswith("{") and start != -1:
        param = template[1:start].strip()
        body_end = _matching_brace(template, 0)
        if param and re.match(r"^\w+$", param) and body_end == len(template) - 1:
            return _plural_expression(param, template[start + len(", plural,"):body_end])
    # Only substitute ICU {placeholder} tokens that are declared as real
    # placeholders in the message. Anything else ({0}, {count, plural, ...}
    # leftovers from a partially-translated string) is dropped so we never
    # emit invalid Dart like `\$0`.
    ph_names = set(placeholders(template))

    def _sub(m: re.Match) -> str:
        name = m.group(1)
        if name not in ph_names:
            return ""
        if name.isidentifier():
            return "\\$" + name
        return "\\${" + name + "}"

    buf = ["'"]
    cursor = 0
    for m in re.finditer(r"\{(\w+)(?:\s*,[^{}]*)?\}", template):
        buf.append(escape_literal(template[cursor : m.start()]))
        buf.append(_sub(m))
        cursor = m.end()
    buf.append(escape_literal(template[cursor:]))
    buf.append("'")
    return "".join(buf)


def _matching_brace(text: str, open_idx: int) -> int:
    """Return the index of the '}' matching the '{' at open_idx."""
    depth = 0
    for i in range(open_idx, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1


def _split_top_level(text: str) -> list[str]:
    """Split ICU plural cases on whitespace that sits outside braces.

    ICU plural blocks separate cases with plain spaces, not commas:
    `=0{Arriving now} other{{minutes} min away}` is two cases. Splitting
    on top-level whitespace keeps selector tokens (which never contain
    spaces) intact while separating each `selector{body}` unit.
    """
    parts, depth, current = [], 0, []
    for ch in text:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        if ch.isspace() and depth == 0:
            if current:
                parts.append("".join(current))
                current = []
        else:
            current.append(ch)
    if current:
        parts.append("".join(current))
    return parts


def _icu_to_dart(chunk: str) -> str:
    """Convert an ICU case body (with {param} tokens) to a Dart literal."""
    out = ["'"]
    cursor = 0
    for m in re.finditer(r"\{(\w+)\}", chunk):
        out.append(escape_literal(chunk[cursor : m.start()]))
        name = m.group(1)
        out.append("\\$" + name if name.isidentifier() else "\\${" + name + "}")
        cursor = m.end()
    out.append(escape_literal(chunk[cursor:]))
    out.append("'")
    return "".join(out)


def _plural_expression(param: str, cases_text: str) -> str:
    """Compile an ICU plural block into a Dart conditional expression.

    Semantically equivalent to the Intl.plural() call that flutter gen-l10n
    would emit, but with no package:intl dependency — matching the style of
    the rest of the committed catalog. Only exact-value selectors (=0, =1,
    =2, ...) are supported; locale-dependent categories (few/many) would
    need CLDR rules and are rejected loudly instead of silently mis-rendered.
    """
    cases = []  # (selector, dart-literal) — selector like '=0' or 'other'
    for piece in _split_top_level(cases_text):
        piece = piece.strip()
        if not piece:
            continue
        m = re.match(r"^(=\d+|\w+)\s*\{", piece)
        if not m:
            sys.exit(f"ERROR: cannot parse plural case: {piece!r}")
        open_idx = piece.index("{", m.end() - 1)
        close_idx = _matching_brace(piece, open_idx)
        if close_idx != len(piece) - 1:
            sys.exit(f"ERROR: trailing text after plural case: {piece!r}")
        cases.append((m.group(1), _icu_to_dart(piece[open_idx + 1 : close_idx])))
    other = next((b for s, b in cases if s == "other"), None)
    if other is None:
        sys.exit(f"ERROR: plural for {param} has no 'other' case")
    explicit = [(s, b) for s, b in cases if s.startswith("=")]
    named = [s for s, _ in cases if not s.startswith("=") and s != "other"]
    if named:
        sys.exit(
            f"ERROR: plural for {param} uses CLDR categories {named}; "
            "this tool only compiles exact-value plurals (=N). Run real "
            "flutter gen-l10n for this message."
        )
    expr = other
    for selector, body in reversed(explicit):
        n = int(selector[1:])
        expr = f"({param} == {n} ? {body} : {expr})"
    return expr


def insert_before_class_end(src: str, additions: str) -> str:
    idx = src.rfind("\n}")
    if idx == -1:
        sys.exit("ERROR: could not locate class end marker")
    return src[:idx] + "\n" + additions + src[idx:]


def main() -> None:
    root = Path("lib/l10n")
    gen = root / "generated"
    en_doc = read_arb(root / "app_en.arb")
    docs = {"en": en_doc, "am": read_arb(root / "app_am.arb"), "om": read_arb(root / "app_om.arb")}

    keys = [k for k in en_doc if not k.startswith("@")]

    abstract_path = gen / "app_localizations.dart"
    abstract_src = abstract_path.read_text(encoding="utf-8")
    subclass_src = {loc: (gen / f"app_localizations_{loc}.dart").read_text(encoding="utf-8") for loc in ARB_KEYS}

    abs_buf, impl_buf = [], {loc: [] for loc in ARB_KEYS}
    added = []

    for key in keys:
        value = en_doc[key]
        if not isinstance(value, str):
            continue  # metadata-only entries carry no message of their own
        ph = placeholders(value)
        is_func = bool(ph)
        has = (
            re.search(rf"String {key}\(", abstract_src)
            if is_func
            else f"String get {key};" in abstract_src
        )
        if has:
            continue  # already generated — leave untouched
        added.append(key)

        meta = en_doc.get(f"@{key}")
        desc = meta.get("description") if isinstance(meta, dict) else None

        abs_buf.append("")
        if desc:
            abs_buf.append(f"  /// {desc}")
            abs_buf.append("  ///")
        else:
            abs_buf.append(f"  /// No description provided for @{key}.")
            abs_buf.append("  ///")
        sample = value.replace("\n", " ")
        abs_buf.append("  /// In en, this message translates to:")
        abs_buf.append(f"  /// **{sample}**")
        if is_func:
            abs_buf.append(f"  String {key}({param_list(ph, meta)});")
        else:
            abs_buf.append(f"  String get {key};")

        for loc in ARB_KEYS:
            text = docs[loc].get(key)
            if not isinstance(text, str):
                text = value  # fall back to template like gen-l10n does
            impl_buf[loc].append("")
            impl_buf[loc].append("  @override")
            if is_func:
                impl_buf[loc].append(f"  String {key}({param_list(ph, meta)}) {{")
                impl_buf[loc].append(f"    return {dart_expression(text)};")
                impl_buf[loc].append("  }")
            else:
                impl_buf[loc].append(f"  String get {key} => '{escape_literal(text)}';")

    if not added:
        print("Catalog already in sync with ARB files; nothing to do.")
        return

    abstract_path.write_text(insert_before_class_end(abstract_src, "\n".join(abs_buf)), encoding="utf-8")
    for loc in ARB_KEYS:
        path = gen / f"app_localizations_{loc}.dart"
        path.write_text(insert_before_class_end(subclass_src[loc], "\n".join(impl_buf[loc])), encoding="utf-8")

    print(f"Added {len(added)} members:")
    for k in added:
        print(f"  - {k}")


if __name__ == "__main__":
    main()
