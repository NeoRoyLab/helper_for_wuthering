# Data provenance

## Sources

- Primary roster and per-character core metadata: [Prydwen.gg character roster](https://www.prydwen.gg/wuthering-waves/characters/).
- Roster page verified on 2026-08-28 and displayed 60 character cards.
- The user also supplied the [Wuthering Waves Fandom wiki](https://wutheringwaves.fandom.com/wiki/Wuthering_Waves_Wiki). Its page returned HTTP 402 through
  the available web reader, so no field in version 1 was taken from Fandom.

Character records contain the source site, verification date, and the source page's displayed
last-updated date. Per-character URLs are intentionally omitted to keep runtime records compact.

## Authored transformations

The following values are repository conventions created for the application, not source claims:

1. Character identifiers are lowercase snake_case versions of English display names.
2. Element and weapon identifiers are normalized to lowercase stable keys.
3. Star labels are stored as integer rarity values (`4` or `5`).
4. File layout, schema version, manifest versions, and JSON Schema are application design.
5. The character manifest is ordered alphabetically by its normalized identifier.

No machine translation or manually authored translation is included. No character description
was copied or rewritten. No image was downloaded from either source.

## Known source limitations

Prydwen listed Hsin, Jingran, and Suoming with core identity data while their detailed skill,
stat, material, build, and team sections were explicitly unavailable. Version 1 stores only the
same core fields for every character, so those missing detailed sections are not fabricated.

Future enrichment must cite a source per added field group and must not silently fill missing
values with guesses, generated prose, or unofficial translations.
