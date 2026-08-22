#!/usr/bin/env python3
"""Extract exports from a Windows PE DLL and emit a .def file for dlltool.

Usage:
    python3 dll_to_def.py <input.dll> <output.def> [dll_basename]

The optional dll_basename is written as the LIBRARY directive in the .def
file (defaults to the basename of input.dll).
"""
import sys
import subprocess


def parse_pe_exports(dll_path):
    """Use objdump to parse the PE export table and return symbol names."""
    out = subprocess.check_output(
        ['i686-w64-mingw32-objdump', '-p', dll_path],
        text=True
    )
    names = []
    for line in out.splitlines():
        # Export entries look like:
        #   \t[   0] +base[   1]  0000 some_symbol_name
        # We skip header lines like "Export RVA" / "Ordinal" / etc.
        if not line.startswith('\t['):
            continue
        if 'Export RVA' in line or 'Ordinal' in line:
            continue
        parts = line.split()
        if len(parts) < 4:
            continue
        name = parts[-1]
        if name in ('RVA', 'Export', 'Ordinal'):
            continue
        names.append(name)
    return names


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    dll_path = sys.argv[1]
    out_def = sys.argv[2]
    dll_basename = sys.argv[3] if len(sys.argv) > 3 else \
        dll_path.rsplit('/', 1)[-1]

    names = parse_pe_exports(dll_path)
    with open(out_def, 'w', newline='\r\n') as f:
        f.write(f'LIBRARY {dll_basename}\r\n')
        f.write('EXPORTS\r\n')
        for n in names:
            f.write(f'  {n}\r\n')
    print(f'Wrote {len(names)} exports to {out_def}', file=sys.stderr)


if __name__ == '__main__':
    main()
