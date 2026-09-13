#!/usr/bin/env python3
"""Exercise the source-graph gate with actual Bash imports and collisions."""
from pathlib import Path
import subprocess
import tempfile
import unittest

CHECKER = Path(__file__).resolve().with_name("test-source-graph.sh")


class SourceGraphTests(unittest.TestCase):
    def check_graph(self, files, expected_status, diagnostic=""):
        with tempfile.TemporaryDirectory(prefix="sbd graph 中文 ") as directory:
            root = Path(directory)
            for name, content in files.items():
                (root / name).write_text(content, encoding="utf-8")
            result = subprocess.run(
                ["bash", str(CHECKER), str(root / "entry.sh")], cwd=root,
                capture_output=True, text=True, timeout=10, check=False,
            )
            self.assertEqual(result.returncode, expected_status, result.stderr)
            self.assertIn(diagnostic, result.stderr)

    def test_distinct_functions_and_repeated_import(self):
        self.check_graph({
            "entry.sh": 'source "./first file.sh"\nsource ./second.sh\nsource ./second.sh\n',
            "first file.sh": "first() { :; }\n",
            "second.sh": "second() { :; }\n",
        }, 0)

    def test_duplicate_definition(self):
        self.check_graph({
            "entry.sh": "source ./first.sh\nsource ./second.sh\n",
            "first.sh": "collision() { :; }\n",
            "second.sh": "collision() { printf broken; }\n",
        }, 1, "Function overwritten in source graph: collision")

    def test_nested_collision_cannot_be_hidden_by_success(self):
        self.check_graph({
            "entry.sh": "source ./nested.sh || :\ntrue\n",
            "nested.sh": "source ./first.sh\nsource ./second.sh\ntrue\n",
            "first.sh": "collision() { :; }\n",
            "second.sh": "collision() { :; }\n",
        }, 1, "Function overwritten in source graph: collision")

    def test_entry_failure_is_preserved(self):
        self.check_graph({"entry.sh": "return 7\n"}, 7)


if __name__ == "__main__":
    unittest.main()
