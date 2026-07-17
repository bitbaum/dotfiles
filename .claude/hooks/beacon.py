#!/usr/bin/env python3
import os
import sys

COCKPIT_BEACON = os.path.expanduser("~/dev/cockpit/scripts/beacon.py")
QT_LIB = os.path.expanduser("~/dev/cockpit/.python-vendor/site-packages/PyQt6/Qt6/lib")
QT_PLUGINS = os.path.expanduser("~/dev/cockpit/.python-vendor/site-packages/PyQt6/Qt6/plugins")

ld = os.environ.get("LD_LIBRARY_PATH", "")
paths = [QT_LIB, "/lib/x86_64-linux-gnu", "/usr/lib/x86_64-linux-gnu"]
if ld:
    paths.append(ld)
os.environ["LD_LIBRARY_PATH"] = ":".join(paths)
os.environ["QT_PLUGIN_PATH"] = QT_PLUGINS

os.execvp("python3", ["python3", COCKPIT_BEACON, *sys.argv[1:]])
