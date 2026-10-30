"""Smoke tests for the WinUtil title-screen framer."""

import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from frame_capture import BORDER_COLOR, frame_capture


class FrameCaptureTests(unittest.TestCase):
    def test_creates_only_requested_title_screen(self):
        with tempfile.TemporaryDirectory(prefix="winutil-frame-test-") as temp_dir:
            work_dir = Path(temp_dir)
            dark_path = work_dir / "dark.png"
            output_path = work_dir / "title-screen.png"

            self._create_capture(dark_path, (32, 34, 36, 255))

            result = frame_capture(dark_path, output_path)

            self.assertEqual(result, output_path)
            self.assertEqual(
                {path.name for path in work_dir.glob("*.png")},
                {"dark.png", "title-screen.png"},
            )
            with Image.open(output_path) as framed:
                self.assertEqual(framed.size, (64, 40))
                self.assertEqual(framed.getpixel((0, 0)), BORDER_COLOR)
                self.assertEqual(framed.getpixel((5, 20)), (32, 34, 36, 255))
                self.assertEqual(framed.getpixel((58, 20)), (32, 34, 36, 255))

    @staticmethod
    def _create_capture(path: Path, content_color: tuple[int, int, int, int]):
        image = Image.new("RGBA", (70, 46), (0, 0, 0, 255))
        draw = ImageDraw.Draw(image)
        draw.rectangle((3, 3, 66, 42), fill=content_color)
        image.save(path, "PNG")


if __name__ == "__main__":
    unittest.main()
