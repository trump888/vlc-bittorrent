#!/usr/bin/env python3
"""Inspect a Windows PE DLL: dump exports and imports (DLL dependencies).

Usage:
    python3 pe_inspect.py exports <input.dll>     # print one export per line
    python3 pe_inspect.py imports <input.dll>     # print one imported DLL per line

This script parses the PE file format directly (no objdump dependency),
so it works consistently across binutils versions and on hosts without
mingw-w64 installed.
"""
import sys
import struct


def rva_to_offset(rva, sections):
    for s in sections:
        if s['virtual_address'] <= rva < s['virtual_address'] + s['virtual_size']:
            return rva - s['virtual_address'] + s['pointer_to_raw_data']
    return None


def read_cstr(data, offset):
    end = data.index(b'\x00', offset)
    return data[offset:end].decode('ascii', errors='replace')


def parse_pe(data):
    """Parse PE header, return (is_pe32_plus, sections, opt_offset, opt_size)."""
    if data[:2] != b'MZ':
        raise ValueError('not a PE file (missing MZ signature)')
    pe_offset = struct.unpack_from('<I', data, 0x3C)[0]
    if data[pe_offset:pe_offset + 4] != b'PE\x00\x00':
        raise ValueError('missing PE signature')

    coff_offset = pe_offset + 4
    machine, num_sections, _ts, _ptr_sym, num_syms, opt_size, _chars = \
        struct.unpack_from('<HHIIIHH', data, coff_offset)

    opt_offset = coff_offset + 20
    magic = struct.unpack_from('<H', data, opt_offset)[0]
    is_pe32_plus = (magic == 0x20b)

    # Parse section table
    section_table_offset = opt_offset + opt_size
    sections = []
    for i in range(num_sections):
        s_off = section_table_offset + i * 40
        virtual_size, virtual_address, raw_size, pointer_to_raw_data = \
            struct.unpack_from('<IIII', data, s_off + 8)
        sections.append({
            'virtual_address': virtual_address,
            'virtual_size': virtual_size,
            'raw_size': raw_size,
            'pointer_to_raw_data': pointer_to_raw_data,
        })

    return is_pe32_plus, sections, opt_offset, opt_size


def get_exports(data, is_pe32_plus, sections, opt_offset):
    """Return list of exported symbol names."""
    if not is_pe32_plus:
        export_dir_rva = struct.unpack_from('<I', data, opt_offset + 96)[0]
    else:
        export_dir_rva = struct.unpack_from('<I', data, opt_offset + 112)[0]
    if export_dir_rva == 0:
        return []

    export_offset = rva_to_offset(export_dir_rva, sections)
    if export_offset is None:
        return []

    # IMAGE_EXPORT_DIRECTORY: skip first 24 bytes, get NumberOfNames + AddressOfNames
    num_names = struct.unpack_from('<I', data, export_offset + 24)[0]
    addr_names = struct.unpack_from('<I', data, export_offset + 32)[0]
    if num_names == 0:
        return []

    names_array_offset = rva_to_offset(addr_names, sections)
    if names_array_offset is None:
        return []

    name_rvas = struct.unpack_from(f'<{num_names}I', data, names_array_offset)
    names = []
    for nrva in name_rvas:
        name_offset = rva_to_offset(nrva, sections)
        if name_offset is None:
            continue
        names.append(read_cstr(data, name_offset))
    return names


def get_imports(data, is_pe32_plus, sections, opt_offset):
    """Return list of imported DLL names (deduplicated, sorted)."""
    # Import directory is data directory index 1
    if not is_pe32_plus:
        import_dir_rva = struct.unpack_from('<I', data, opt_offset + 104)[0]
    else:
        import_dir_rva = struct.unpack_from('<I', data, opt_offset + 120)[0]
    if import_dir_rva == 0:
        return []

    import_offset = rva_to_offset(import_dir_rva, sections)
    if import_offset is None:
        return []

    # IMAGE_IMPORT_DESCRIPTOR (20 bytes): OriginalFirstThunk, TimeDateStamp,
    # ForwarderChain, Name (RVA to DLL name), FirstThunk
    # The array is terminated by an all-zero entry.
    dll_names = set()
    i = 0
    while True:
        desc_offset = import_offset + i * 20
        if desc_offset + 20 > len(data):
            break
        oft, _ts, _fc, name_rva, _ft = \
            struct.unpack_from('<IIIII', data, desc_offset)
        if oft == 0 and name_rva == 0 and _ft == 0:
            break  # terminator
        if name_rva != 0:
            name_offset = rva_to_offset(name_rva, sections)
            if name_offset is not None:
                dll_names.add(read_cstr(data, name_offset).lower())
        i += 1

    return sorted(dll_names)


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ('exports', 'imports'):
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    what = sys.argv[1]
    dll_path = sys.argv[2]

    with open(dll_path, 'rb') as f:
        data = f.read()

    is_pe32_plus, sections, opt_offset, opt_size = parse_pe(data)

    if what == 'exports':
        for name in get_exports(data, is_pe32_plus, sections, opt_offset):
            print(name)
    else:  # imports
        for name in get_imports(data, is_pe32_plus, sections, opt_offset):
            print(name)


if __name__ == '__main__':
    main()
