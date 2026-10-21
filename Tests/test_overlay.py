import importlib.util
import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("overlay", HERE / "apply.py")
overlay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(overlay)


class CatalogTests(unittest.TestCase):
    def test_insertion_preserves_existing_locales(self):
        original = json.dumps({"sourceLanguage": "en", "strings": {
            'A "quote"': {"comment": "{keep}", "localizations": {"de": {"stringUnit": {"state": "translated", "value": "B"}}}},
            "skip": {"shouldTranslate": False}}})
        edited = overlay.catalog_edit(original, {'A "quote"': "نص", "skip": "تجاوز"})
        parsed = json.loads(edited)
        del parsed["strings"]['A "quote"']["localizations"]["ar"]
        self.assertEqual(parsed, json.loads(original))
        self.assertEqual(edited, overlay.catalog_edit(edited, {'A "quote"': "نص"}))

    def test_empty_entry_and_update(self):
        original = '{"sourceLanguage":"en","strings":{"Save":{}}}'
        first = overlay.catalog_edit(original, {"Save": "حفظ"})
        updated = overlay.catalog_edit(first, {"Save": "حفظ التغييرات"})
        self.assertEqual(json.loads(updated)["strings"]["Save"]["localizations"]["ar"]["stringUnit"]["value"], "حفظ التغييرات")

    def test_translation_keys_unique(self):
        def pairs(values):
            result = {}
            for key, value in values:
                self.assertNotIn(key, result)
                result[key] = value
            return result
        json.loads((HERE / "ar.json").read_text(), object_pairs_hook=pairs)


if __name__ == "__main__": unittest.main()
