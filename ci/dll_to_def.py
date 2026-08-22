#!/usr/bin/env python3
"""Extract exports from a Windows PE DLL and emit a .def file for dlltool.

Usage:
    python3 dll_to_def.py <input.dll> <output.def> [dll_basename]

The optional dll_basename is written as the LIBRARY directive in the .def
file (defaults to the basename of input.dll).

This script parses the PE file format directly (no objdump dependency).
It handles both PE32 (i386) and PE32+ (x86_64) binaries, including the
Edge Case where the export directory's AddressOfNames points to RVAs that
need to be resolved against the section table.
"""
import sys
import struct


def rva_to_offset(rva, sections):
    """Convert a Relative Virtual Address to a file offset using the section table."""
    for s in sections:
        if s['virtual_address'] <= rva < s['virtual_address'] + s['virtual_size']:
            return rva - s['virtual_address'] + s['pointer_to_raw_data']
    return None


def parse_pe_exports(dll_path):
    """Parse the PE export directory and return a list of exported symbol names."""
    with open(dll_path, 'rb') as f:
        data = f.read()

    # DOS header: e_lfanew at offset 0x3C tells us where the PE header starts
    if data[:2] != b'MZ':
        raise ValueError(f'{dll_path}: not a PE file (missing MZ signature)')
    pe_offset = struct.unpack_from('<I', data, 0x3C)[0]
    if data[pe_offset:pe_offset + 4] != b'PE\x00\x00':
        raise ValueError(f'{dll_path}: missing PE signature')

    # COFF header (20 bytes)
    coff_offset = pe_offset + 4
    machine, num_sections, _ts, _ptr_sym, num_syms, opt_size, _chars = \
        struct.unpack_from('<HHIIIHH', data, coff_offset)

    # Optional header starts right after COFF header
    opt_offset = coff_offset + 20
    magic = struct.unpack_from('<H', data, opt_offset)[0]
    if magic == 0x10b:
        # PE32 (i386)
        is_pe32_plus = False
        # Image base at offset 28 in optional header (4 bytes)
        image_base = struct.unpack_from('<I', data, opt_offset + 28)[0]
        # Export directory RVA is in the data directory at offset 96 in opt header
        # (offset 0 of data dir = export, 4 bytes RVA + 4 bytes size)
        export_dir_rva = struct.unpack_from('<I', data, opt_offset + 96)[0]
        export_dir_size = struct.unpack_from('<I', data, opt_offset + 100)[0]
    elif magic == 0x20b:
        # PE32+ (x86_64)
        is_pe32_plus = True
        # Image base at offset 24 in optional header (8 bytes)
        image_base = struct.unpack_from('<Q', data, opt_offset + 24)[0]
        # Export directory RVA is in the data directory at offset 112 in opt header
        export_dir_rva = struct.unpack_from('<I', data, opt_offset + 112)[0]
        export_dir_size = struct.unpack_from('<I', data, opt_offset + 116)[0]
    else:
        raise ValueError(f'{dll_path}: unknown optional header magic 0x{magic:04x}')

    if export_dir_rva == 0 or export_dir_size == 0:
        return []

    # Parse section table (starts after optional header)
    section_table_offset = opt_offset + opt_size
    sections = []
    for i in range(num_sections):
        s_off = section_table_offset + i * 40
        _name = data[s_off:s_off + 8].rstrip(b'\x00').decode('ascii', errors='replace')
        virtual_size, virtual_address, raw_size, pointer_to_raw_data = \
            struct.unpack_from('<IIII', data, s_off + 8)
        sections.append({
            'name': _name,
            'virtual_address': virtual_address,
            'virtual_size': virtual_size,
            'raw_size': raw_size,
            'pointer_to_raw_data': pointer_to_raw_data,
        })

    # Resolve export directory RVA to file offset
    export_offset = rva_to_offset(export_dir_rva, sections)
    if export_offset is None:
        raise ValueError(f'{dll_path}: cannot resolve export directory RVA {export_dir_rva:#x}')

    # IMAGE_EXPORT_DIRECTORY structure (40 bytes):
    #   0  DWORD Characteristics
    #   4  DWORD TimeDateStamp
    #   8  WORD  MajorVersion
    #  10  WORD  MinorVersion
    #  12  DWORD Name (RVA to DLL name string)
    #  16  DWORD Base (ordinal base)
    #  20  DWORD NumberOfFunctions
    #  24  DWORD NumberOfNames
    #  28  DWORD AddressOfFunctions (RVA)
    #  32  DWORD AddressOfNames (RVA)
    #  36  DWORD AddressOfNameOrdinals (RVA)
    _chars, _ts, _maj, _min, name_rva, ordinal_base, \
        num_funcs, num_names, _addr_funcs, addr_names, addr_ordinals = \
        struct.unpack_from('<IIHHIIIIIII', data, export_offset)

    if num_names == 0:
        return []

    # Resolve AddressOfNames RVA -> array of name RVAs
    names_array_offset = rva_to_offset(addr_names, sections)
    if names_array_offset is None:
        raise ValueError(f'{dll_path}: cannot resolve AddressOfNames RVA {addr_names:#x}')

    # Read num_names name RVAs (each 4 bytes)
    name_rvas = struct.unpack_from(f'<{num_names}I', data, names_array_offset)

    # Resolve each name RVA to a file offset, then read the null-terminated string
    names = []
    for nrva in name_rvas:
        name_offset = rva_to_offset(nrva, sections)
        if name_offset is None:
            continue
        end = data.index(b'\x00', name_offset)
        name = data[name_offset:end].decode('ascii', errors='replace')
        if name:
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
