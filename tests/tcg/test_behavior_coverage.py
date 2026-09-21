import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
COVERAGE = ROOT / "tools/tcg/behavior_coverage.json"
PENDING = ROOT / "tools/tcg/behavior_pending.json"


class BehaviorCoverageTests(unittest.TestCase):
    def load(self):
        return json.loads(COVERAGE.read_text(encoding="utf-8"))

    def test_translated_targets_exist(self):
        data = self.load()
        self.assertEqual(data["schema"], 1)
        for row in data["entries"]:
            self.assertEqual(row["state"], "translated")
            self.assertTrue((ROOT / row["target"]).is_file(), row["target"])
            self.assertTrue(row["labels"], row["source"])

    def test_source_labels_are_not_double_claimed(self):
        seen = set()
        for row in self.load()["entries"]:
            for label in row["labels"]:
                key = (row["source"], label)
                self.assertNotIn(key, seen, f"duplicate behavior mapping: {key}")
                seen.add(key)

    def test_partial_behavior_is_separate_from_translated_coverage(self):
        translated = self.load()
        pending = json.loads(PENDING.read_text(encoding="utf-8"))
        translated_labels = {
            (row["source"], label)
            for row in translated["entries"]
            for label in row["labels"]
        }
        self.assertEqual(pending["schema"], 1)
        for row in pending["entries"]:
            self.assertEqual(row["state"], "partial")
            self.assertTrue(row["remaining"])
            self.assertTrue((ROOT / row["target"]).is_file())
            for label in row["labels"]:
                self.assertNotIn((row["source"], label), translated_labels)



if __name__ == "__main__":
    unittest.main()
