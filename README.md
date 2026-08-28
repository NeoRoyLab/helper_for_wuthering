# helper_for_wuthering

Versioned cloud content for the Helper for Wuthering application.

## Current scope

Version 1 contains the core roster used by character lists and filters:

- 60 character records;
- English display name;
- rarity;
- element;
- weapon type;
- per-record source and verification date.

The repository intentionally does not contain Unity project files. Character descriptions,
stats, skills, builds, materials, translations, and images are not part of this first version.

## Layout

```text
manifest.json
manifests/characters.json
characters/<id>/data.json
data/elements.json
data/weapon_types.json
schema/character.schema.json
tools/validate_content.ps1
```

See `DATA_PROVENANCE.md` before adding or changing content.
