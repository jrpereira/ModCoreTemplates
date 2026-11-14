# Vendored from ModCoreSettings (owner). Do not edit copies; change the source and re-vendor.
"""Manifest path checks shared by packaging. Never deploys, stops or launches a game."""
from pathlib import Path, PurePosixPath

def safe_file(root, relative):
    p = PurePosixPath(relative)
    if p.is_absolute() or '..' in p.parts or '\\' in relative or ':' in relative:
        raise ValueError('Manifest paths must be relative POSIX paths')
    target = (Path(root) / relative).resolve()
    if not target.is_relative_to(Path(root).resolve()):
        raise ValueError('Manifest path escapes payload root')
    return target
