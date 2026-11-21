"""Small file helpers for lecture-08-notebook.py.

    list_files("files")        a table of every file under a folder, with its size
    clean_class_files()        delete what the notebook writes during class,
                               so the "write a file" steps can be shown again

Paths are relative to lecture_8/ (the notebook changes into that folder).
"""

import shutil
from pathlib import Path

import pandas as pd

# Written by the notebook (Parts 4 and 6) and by pipeline/run.py (Part 8).
# NOT the files steps/00-make-files.py writes: those the lecture reads from.
# A pattern with * deletes the matching files and keeps the folder.
CLASS_FILES = [
    "files/by_month",
    "files/orders_2025.parquet",
    "files/shop_orders.parquet",
    "files/june_2025.*",
    "pipeline/data/raw/*.parquet",
    "pipeline/data/reports/*.parquet",
]


def list_files(folder):
    """Every file under `folder` (and its sub-folders), with its size in MB (1 MB = 1,000,000 bytes)."""
    folder = Path(folder)
    rows = [{"file": str(p), "mb": round(p.stat().st_size / 1e6, 1)}
            for p in sorted(folder.rglob("*")) if p.is_file() and not p.name.startswith(".")]
    return pd.DataFrame(rows, columns=["file", "mb"])


def clean_class_files():
    """Delete the files and folders in CLASS_FILES that exist; return what was deleted."""
    removed = []
    for name in CLASS_FILES:
        if "*" in name:
            for f in sorted(Path().glob(name)):
                f.unlink()
                removed.append(str(f))
            continue
        p = Path(name)
        if p.is_dir():
            shutil.rmtree(p)
            removed.append(name + "/")
        elif p.exists():
            p.unlink()
            removed.append(name)
    return removed
