# helper_for_wuthering

Versioned cloud content for the Helper for Wuthering application.

## Current scope

The current local content set contains the version 2 character roster and version 1 guides:

- 60 character records;
- English display name;
- rarity;
- element;
- weapon type;
- exact 404x560 PNG Convene Draw artwork where that asset exists on the supplied wiki;
- per-record source and verification date.
- 57 character guide records with Prydwen weapon and Echo Set ordering;
- 72 normalized weapon records and exact wiki PNG icons;
- 29 normalized Echo Set records, exact wiki piece-bonus text, and exact wiki PNG icons;
- explicit source URLs, source page dates/revisions, hashes, and three documented guide gaps.

The repository intentionally does not contain Unity project files. Character descriptions,
stats, skills, materials, recommendation prose, and translations are not part of this version.

## Layout

```text
manifest.json
manifests/characters.json
manifests/character_images.json
manifests/guides.json
manifests/guide_assets.json
characters/<id>/data.json
characters/<id>/convene_draw.png
guides/<character_id>/data.json
weapons/<id>/data.json
weapons/<id>/icon.png
echo_sets/<id>/data.json
echo_sets/<id>/icon.png
data/elements.json
data/weapon_types.json
schema/character.schema.json
schema/guide.schema.json
schema/weapon.schema.json
schema/echo_set.schema.json
tools/validate_content.ps1
tools/sync_convene_draws.ps1
tools/sync_guides.ps1
tools/prydwen_guide_snapshot.json
```

See `DATA_PROVENANCE.md` before adding or changing content.
