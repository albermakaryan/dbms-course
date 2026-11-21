"""Logging for the pipeline: every step logs to the console and to logs/pipeline.log.

Each module asks for its own logger, e.g. logging.getLogger("pipeline.extract");
setup() is called once, by run.py.
"""

import logging
import sys

from .config import LOGS

FORMAT = "%(asctime)s %(levelname)-7s %(name)-19s %(message)s"


def setup(level=logging.INFO):
    """Send every "pipeline.*" logger to the console and to logs/pipeline.log (appended)."""
    logger = logging.getLogger("pipeline")
    if logger.handlers:                         # already set up (e.g. a notebook re-runs the cell)
        return logger
    LOGS.mkdir(parents=True, exist_ok=True)
    (LOGS / ".gitkeep").touch(exist_ok=True)
    formatter = logging.Formatter(FORMAT, datefmt="%Y-%m-%d %H:%M:%S")
    for handler in (logging.StreamHandler(sys.stdout), logging.FileHandler(LOGS / "pipeline.log")):
        handler.setFormatter(formatter)
        logger.addHandler(handler)
    logger.setLevel(level)
    logger.propagate = False                    # don't print everything twice
    return logger
