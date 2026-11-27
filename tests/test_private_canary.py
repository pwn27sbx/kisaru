"""The private source canary is an offline contract check only."""

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import source_canary


class Module:
    search = staticmethod(lambda *args, **kwargs: [])
    series = staticmethod(lambda *args, **kwargs: {})
    links = staticmethod(lambda *args, **kwargs: [])


class PrivateCanaryTest(unittest.TestCase):
    def test_source_is_listed(self):
        self.assertIn("private_anime", source_canary.SOURCES)

    def test_contract_check_never_fetches_or_uses_manga_chain(self):
        def forbidden(*args, **kwargs):
            raise AssertionError("network or chain must not run")

        with mock.patch.object(source_canary, "check_chain", side_effect=forbidden):
            lines, code = source_canary.run(
                ["private_anime"], {"private_anime": Module()}, forbidden, chain=True
            )
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["ok   private_anime: offline-contract"])

    def test_disabled_contract_is_a_fixed_skip(self):
        with mock.patch.dict(os.environ, {"QS_HENTAILA_SOURCE": "off"}):
            lines, code = source_canary.run(
                ["private_anime"], {"private_anime": Module()}, chain=False
            )
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["skip private_anime: disabled"])


if __name__ == "__main__":
    unittest.main()
