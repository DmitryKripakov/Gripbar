"""Print Gripbar's debug log (GripbarDebugLog) from the SavedVariables file.

    python tools/readlog.py [path/to/SavedVariables/Gripbar.lua] [--lines N]

Without a path it looks for WTF/Account/*/SavedVariables/Gripbar.lua next to
the addon. Shows the sessions, every distinct problem (errors, blocked
actions, warnings) with counts, then the last N timeline lines.
"""
import glob
import os
import re
import sys


def find_file():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    found = glob.glob(os.path.join(root, "WTF", "Account", "*", "SavedVariables", "Gripbar.lua"))
    return found[0] if found else None


def lua_strings(block):
    """The quoted strings of a Lua table block, unescaped."""
    out = []
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', block):
        out.append(m.group(1).replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\'))
    return out


def section(text, name):
    m = re.search(r'\["%s"\] = \{' % name, text)
    if not m:
        return ""
    depth, i = 1, m.end()
    while depth and i < len(text):
        if text[i] == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == '\\' else 1
        elif text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
        i += 1
    return text[m.end():i - 1]


def records(block):
    """Top-level {...} records of a list block as dicts of key -> value."""
    result, depth, start = [], 0, None
    i = 0
    while i < len(block):
        c = block[i]
        if c == '"':
            i += 1
            while block[i] != '"':
                i += 2 if block[i] == '\\' else 1
        elif c == '{':
            if depth == 0:
                start = i
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                body = block[start + 1:i]
                fields = {}
                for fm in re.finditer(r'\["(\w+)"\] = ("((?:[^"\\]|\\.)*)"|[-\d.]+|true|false)', body):
                    value = fm.group(3) if fm.group(3) is not None else fm.group(2)
                    fields[fm.group(1)] = value.replace('\\n', '\n').replace('\\"', '"')
                result.append(fields)
        i += 1
    return result


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    count = 60
    if "--lines" in sys.argv:
        count = int(sys.argv[sys.argv.index("--lines") + 1])
        args = [a for a in args if a != str(count)]
    path = args[0] if args else find_file()
    if not path or not os.path.exists(path):
        sys.exit("Gripbar.lua not found")
    text = open(path, encoding="utf-8", errors="replace").read()
    log = text[text.find("GripbarDebugLog"):]
    print("File:", path, "| modified:", os.path.getmtime(path))
    print("\n== Sessions ==")
    for s in records(section(log, "sessions")):
        print(f"#{s.get('session')} {s.get('start')}  client {s.get('client')}  Gripbar {s.get('gripbar')}")
    print("\n== Problems ==")
    problems = records(section(log, "problems"))
    if not problems:
        print("none")
    for p in sorted(problems, key=lambda r: r.get("last", "")):
        print(f"[{p.get('kind')}] x{p.get('count')}  sessions #{p.get('firstSession')}..#{p.get('lastSession')}  "
              f"{p.get('first')} .. {p.get('last')}")
        print("   " + p.get("text", "").replace("\n", "\n   "))
        if p.get("stack"):
            print("   stack: " + p["stack"].strip().replace("\n", "\n          "))
    print(f"\n== Last {count} timeline lines ==")
    for line in lua_strings(section(log, "lines"))[-count:]:
        print(line[:400])


if __name__ == "__main__":
    main()
