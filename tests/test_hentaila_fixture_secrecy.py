"""Fixtures for the private source must not retain live source data."""

import os
import re
import unittest

FIX = os.path.join(os.path.dirname(__file__), "fixtures", "hentaila")


class FixtureSecrecyTest(unittest.TestCase):
    def test_no_live_urls_tokens_or_tracking_data(self):
        forbidden = (
            re.compile(r"https?://", re.I),
            re.compile(r"[?&](?:token|time|key|sig)=", re.I),
            re.compile(r"(?:cookie|authorization)\s*[:=]", re.I),
            re.compile(r"data:image/", re.I),
            re.compile(r"eyJ[A-Za-z0-9_-]{20,}"),
        )
        for name in sorted(os.listdir(FIX)):
            path = os.path.join(FIX, name)
            if not os.path.isfile(path):
                continue
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            for pattern in forbidden:
                with self.subTest(fixture=name, pattern=pattern.pattern):
                    self.assertIsNone(pattern.search(text))


if __name__ == "__main__":
    unittest.main()
