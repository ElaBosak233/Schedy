#!/usr/bin/env python3
"""Check key naming, source references, translations, and format argument compatibility."""
import json
from pathlib import Path
import re
import sys
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
KEY = re.compile(r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+")
REFERENCE = re.compile(r'(?:String\(\s*localized:\s*|LocalizedStringResource\(\s*|localizedUserNotificationString\(forKey:\s*)"([^"\n]+)"')
FORMAT = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|d|lf|f)")


def values(localization):
    if "stringUnit" in localization:
        yield localization["stringUnit"]["value"]
    else:
        for variants in localization["variations"].values():
            for variant in variants.values():
                yield from values(variant)


def arguments(value):
    return Counter((int(match[1]) if match[1] else index, match[2])
                   for index, match in enumerate(FORMAT.finditer(value), start=1))


for target in ("Schedy", "SchedyWidget"):
    catalog = json.loads((ROOT / target / "Localizable.xcstrings").read_text())
    assert catalog["sourceLanguage"] == "en"
    entries = catalog["strings"]
    for key, entry in entries.items():
        assert KEY.fullmatch(key), f"{target}: nonsemantic key {key!r}"
        translations = entry["localizations"]
        assert {"en", "zh-Hans"} <= translations.keys(), f"{key}: missing language"
        expected = arguments(next(values(translations["en"])))
        for language, translation in translations.items():
            for value in values(translation):
                assert value and arguments(value) == expected, f"{key}: incompatible {language} arguments"
    references = set()
    for path in (ROOT / target).rglob("*.swift"):
        references.update(REFERENCE.findall(path.read_text()))
    assert references == entries.keys(), f"{target}: missing {references - entries.keys()}, unused {entries.keys() - references}"
    if len(sys.argv) > 1:
        app_path = Path(sys.argv[1]).resolve()
        target_name = "SchedyWidgetExtension" if target == "SchedyWidget" else "Schedy"
        intermediates = app_path.parents[2] / "Intermediates.noindex" / "Schedy.build" / app_path.parent.name / (target_name + ".build")
        extracted = list(intermediates.rglob("*.stringsdata"))
        assert extracted, f"Missing compiler localization data: {intermediates}"
        compiler_keys = set()
        for path in extracted:
            if path.name.startswith("Generated"):
                continue
            tables = json.loads(path.read_text()).get("tables", {})
            compiler_keys.update(item["key"] for item in tables.get("Localizable", []))
        assert not compiler_keys - entries.keys(), f"{target}: uncatalogued compiler keys {compiler_keys - entries.keys()}"
    print(f"{target}: {len(entries)} semantic keys, source references and translation arguments verified.")
