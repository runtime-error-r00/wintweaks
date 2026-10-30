"""Generate WinUtil's Dark Tweaks title-screen image.

The automation targets a strictly validated WinUtil WPF window, selects the
Tweaks tab, and captures the window. The raw capture lives in a temporary
directory; only the requested framed output persists.

Local execution must use the same elevation level as WinUtil. CI may provide
``WINUTIL_HWND`` to bypass desktop discovery after launching a known window.
The current maximized WPF bounds determine the capture dimensions.
"""

from __future__ import annotations

import argparse
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageStat
from pywinauto.application import Application

from capture_winutil import (
    capture_window,
    find_winutil_hwnd,
    get_window_capture_size,
)
from frame_capture import frame_capture


CONTROL_TIMEOUT_SECONDS = 10
TAB_SETTLE_SECONDS = 1.0
WINDOW_SETTLE_SECONDS = 0.5
THEME_BRIGHTNESS_THRESHOLD = 128


def is_dark_mode(image: Image.Image) -> bool:
    """Return whether the stable center band resembles WinUtil's Dark theme.

    The center band avoids the title-bar icons and outer DWM frame. Current Dark
    captures average roughly 30-40 luminance, well below the midpoint threshold,
    so a bright capture means the window was covered or not fully drawn.
    """
    width, height = image.size
    sample = image.crop(
        (
            width // 4,
            height // 2 - 10,
            3 * width // 4,
            height // 2 + 10,
        )
    ).convert("L")
    return ImageStat.Stat(sample).mean[0] < THEME_BRIGHTNESS_THRESHOLD


def capture_dark(
    hwnd,
    width: int,
    height: int,
    output_path: str | Path,
) -> Image.Image:
    """Capture WinUtil and reject a capture that does not look like its Dark UI."""
    image = capture_window(hwnd, width, height, output_path)
    if not is_dark_mode(image):
        raise RuntimeError(
            "Expected WinUtil's Dark theme, but the capture looks bright. Make "
            "sure no other window covers WinUtil."
        )
    return image


def maximize_window(hwnd) -> tuple[int, int]:
    """Maximize WinUtil and return its refreshed physical capture dimensions."""
    app = Application(backend="win32").connect(
        handle=hwnd,
        timeout=CONTROL_TIMEOUT_SECONDS,
    )
    window = app.window(handle=hwnd).wrapper_object()
    window.maximize()
    time.sleep(WINDOW_SETTLE_SECONDS)
    return get_window_capture_size(hwnd)


def select_tweaks_tab(hwnd) -> None:
    """Select the Tweaks tab through its stable WPF automation identifier."""
    app = Application(backend="uia").connect(
        handle=hwnd,
        timeout=CONTROL_TIMEOUT_SECONDS,
    )
    window = app.window(handle=hwnd)
    tweaks_spec = window.child_window(
        auto_id="WPFTab2BT",
        control_type="Button",
    )
    try:
        tweaks_spec.wait(
            "exists enabled visible ready",
            timeout=CONTROL_TIMEOUT_SECONDS,
        )
        tweaks_button = tweaks_spec.wrapper_object()
    except Exception as exc:
        raise RuntimeError(
            f"Tweaks button WPFTab2BT was not available in HWND {hex(hwnd)}. "
            "Confirm WinUtil is fully loaded and run at the same elevation level."
        ) from exc

    window.set_focus()
    tweaks_button.click_input()
    time.sleep(TAB_SETTLE_SECONDS)


def generate_title_screen(output_path: str | Path) -> Path:
    """Capture the Dark theme and write one framed title-screen image."""
    output_path = Path(output_path)

    print("Locating WinUtil window...")
    hwnd, _, _ = find_winutil_hwnd()

    print("Maximizing WinUtil...")
    width, height = maximize_window(hwnd)

    print("Selecting Tweaks tab...")
    select_tweaks_tab(hwnd)

    with tempfile.TemporaryDirectory(prefix="winutil-title-screen-") as temp_dir:
        dark_path = Path(temp_dir) / "winutil-dark.png"

        print("Capturing Dark theme...")
        capture_dark(hwnd, width, height, dark_path)

        print("Framing title screen...")
        frame_capture(dark_path, output_path)

    return output_path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture WinUtil's Dark Tweaks title screen."
    )
    parser.add_argument("--output", required=True, type=Path, help="Destination PNG")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    generate_title_screen(args.output)


if __name__ == "__main__":
    main()
