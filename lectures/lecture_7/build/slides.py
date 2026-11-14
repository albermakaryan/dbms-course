"""The diagrams now live in ../notebook_tools/diagrams.py (used by the
notebook). This module only re-exports them for build_notebook.py."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from notebook_tools.diagrams import IN_NOTEBOOK, SIMPLE, SLIDES, by_key, render  # noqa: E402,F401
