# Data provenance

## Sources

- Primary roster and per-character core metadata: [Prydwen.gg character roster](https://www.prydwen.gg/wuthering-waves/characters/).
- Roster page verified on 2026-08-28 and displayed 60 character cards.
- Character Convene Draw artwork: [Wuthering Waves Fandom wiki](https://wutheringwaves.fandom.com/wiki/Wuthering_Waves_Wiki),
  verified through its MediaWiki API on 2026-08-29.

Character records contain the source site, verification date, the source page's displayed
last-updated date, and an optional repository-relative `convene_draw` path. Per-character source
URLs are intentionally omitted to keep runtime records compact. Exact wiki filenames, dimensions,
and SHA-256 hashes are recorded in `manifests/character_images.json`.

## Authored transformations

The following values are repository conventions created for the application, not source claims:

1. Character identifiers are lowercase snake_case versions of English display names.
2. Element and weapon identifiers are normalized to lowercase stable keys.
3. Star labels are stored as integer rarity values (`4` or `5`).
4. File layout, schema version, manifest versions, and JSON Schema are application design.
5. The character manifest is ordered alphabetically by its normalized identifier.
6. Convene Draw assets are renamed to the repository convention `convene_draw.png`; their image
   pixels are copied unchanged from the wiki PNG files.
7. The image manifest and its unavailable-reason text are application-maintained provenance metadata.

No machine translation or manually authored translation is included. No character description
was copied or rewritten.

## Known source limitations

Prydwen listed Hsin, Jingran, and Suoming with core identity data while their detailed skill,
stat, material, build, and team sections were explicitly unavailable. Version 1 stores only the
same core fields for every character, so those missing detailed sections are not fabricated.

Future enrichment must cite a source per added field group and must not silently fill missing
values with guesses, generated prose, or unofficial translations.

The wiki API returned exact 404x560 PNG Convene Draw files for 53 roster entries. It did not return
such a file for Hsin, Jingran, or Suoming. Rover is not represented by a character Convene Draw
file, so the four element-specific Rover records also have no `convene_draw` path. No card art,
splash art, local Unity asset, generated image, or other substitute was used for these seven entries.
