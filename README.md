# helper_for_wuthering

Versioned cloud content for the Helper for Wuthering application.

## Current scope

Version 2 contains the core roster used by character lists and filters:

- 60 character records;
- English display name;
- rarity;
- element;
- weapon type;
- exact 404x560 PNG Convene Draw artwork where that asset exists on the supplied wiki;
- per-record source and verification date.

The repository intentionally does not contain Unity project files. Character descriptions,
stats, skills, builds, materials, and translations are not part of this version.

## Layout

```text
manifest.json
manifests/characters.json
manifests/character_images.json
characters/<id>/data.json
characters/<id>/convene_draw.png
data/elements.json
data/weapon_types.json
schema/character.schema.json
tools/validate_content.ps1
tools/sync_convene_draws.ps1
```

See `DATA_PROVENANCE.md` before adding or changing content.
