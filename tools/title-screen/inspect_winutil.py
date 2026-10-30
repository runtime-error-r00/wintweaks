"""Write WinUtil window and UI Automation diagnostics to an explicit path.

The inspector records the visible desktop windows and the WinUtil window's UI
Automation tree. It must run at the same integrity level as WinUtil.
"""

from __future__ import annotations

import argparse
import contextlib
from pathlib import Path

from pywinauto import Desktop
from pywinauto.application import Application

from capture_winutil import find_winutil_hwnd


def dump_tree(element, depth: int = 0, max_depth: int = 6) -> None:
    """Print a bounded UI Automation subtree without failing on stale elements."""
    if depth > max_depth:
        return

    indent = "  " * depth
    try:
        control_type = element.element_info.control_type
        name = element.element_info.name or ""
        automation_id = element.element_info.automation_id or ""
        class_name = element.element_info.class_name or ""
        print(
            f"{indent}[{control_type}] name={name!r:40s} "
            f"auto_id={automation_id!r:30s} class={class_name!r}"
        )
    except Exception as exc:
        print(f"{indent}<element inspection failed: {exc}>")
        return

    try:
        children = element.children()
    except Exception as exc:
        print(f"{indent}<child enumeration failed: {exc}>")
        return
    for child in children:
        dump_tree(child, depth + 1, max_depth)


def inspect_winutil() -> None:
    """Print desktop and WinUtil diagnostics."""
    print("=== All visible top-level windows (win32 backend) ===")
    for window in Desktop(backend="win32").windows():
        try:
            if window.is_visible():
                print(
                    f"  title={window.window_text()!r:50s} "
                    f"class={window.class_name()!r}"
                )
        except Exception as exc:
            print(f"  <window inspection failed: {exc}>")

    print("\n=== Looking for WinUtil (shared strict lookup) ===")
    winutil_hwnd, _, _ = find_winutil_hwnd()

    print("\n=== Control tree via UIA backend ===")
    try:
        app = Application(backend="uia").connect(handle=winutil_hwnd)
        window = app.window(handle=winutil_hwnd)
        dump_tree(window)
    except Exception as exc:
        raise RuntimeError(
            "UI Automation inspection failed. Run at the same elevation level "
            "as WinUtil."
        ) from exc


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write WinUtil UI Automation diagnostics."
    )
    parser.add_argument("output", type=Path, help="Destination text file")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    failure = None
    # Preserve diagnostics even when discovery or UIA access fails, then return a
    # non-zero exit so local callers and CI do not mistake the dump for success.
    with args.output.open("w", encoding="utf-8") as output_file:
        with contextlib.redirect_stdout(output_file):
            try:
                inspect_winutil()
            except Exception as exc:
                print(f"\nInspection failed: {exc}")
                if exc.__cause__:
                    print(f"Cause: {exc.__cause__}")
                failure = exc

    print(f"Diagnostics written to {args.output}")
    if failure:
        raise failure


if __name__ == "__main__":
    main()
