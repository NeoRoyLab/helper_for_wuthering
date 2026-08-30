# Data provenance

## Sources

- Primary roster and per-character core metadata: [Prydwen.gg character roster](https://www.prydwen.gg/wuthering-waves/characters/).
- Roster page verified on 2026-08-28 and displayed 60 character cards.
- Character Convene Draw artwork: [Wuthering Waves Fandom wiki](https://wutheringwaves.fandom.com/wiki/Wuthering_Waves_Wiki),
  verified through its MediaWiki API on 2026-08-29.
- Character profile descriptions: the introductory profile text on each Wuthering Waves Wiki
  character page, verified through exact page revisions on 2026-08-30.
- Character Level 90 HP, ATK, and DEF: the Wuthering Waves Wiki
  `Module:Resonator Ascensions and Stats/data` revision recorded in
  `manifests/character_profiles.json`, verified on 2026-08-30.
- Per-character build ordering: the visible Build tab of each
  [Prydwen character guide](https://www.prydwen.gg/wuthering-waves/characters), verified on 2026-08-30.
- Weapon names, rarity, type, and icon PNGs; Echo Set names, piece bonuses, and icon PNGs;
  primary Echo names and available icon PNGs:
  [Wuthering Waves Fandom wiki](https://wutheringwaves.fandom.com/wiki/Wuthering_Waves_Wiki),
  verified through exact page revisions and file metadata on 2026-08-30.

Character records contain source metadata for the original core fields, exact wiki page and module
revisions for profile fields, and optional repository-relative `convene_draw`, `icon`, and
`full_sprite` paths. Exact wiki filenames, dimensions, and SHA-256 hashes are recorded in
`manifests/character_images.json`.

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
8. Guide records keep, in visible Prydwen order, at most the first five weapon recommendations, all
   visible standard and special Echo Set recommendations, the first primary Echo option of the first
   ranked Echo Set, all five main-stat slots, and the displayed substat priority. Prydwen percentages
   and recommendation prose are not copied.
9. Weapon, Echo Set, and Echo identifiers are lowercase snake_case application keys. Diacritics are
   removed, apostrophes are removed,
   `&` becomes `and`, and other punctuation becomes a separator. Wiki PNGs are renamed to `icon.png`;
   their pixels are copied unchanged and recorded with dimensions and SHA-256 hashes.
10. Wiki link, color-template, line-break, emphasis, HTML-entity, and soft-hyphen markup is removed
    mechanically from Echo Set bonuses for runtime display. Wording is not translated or rewritten.
11. Prydwen's `Endless Resonance` recommendation is linked to the wiki's `Lingering Tunes` content.
    This is the only source-name reconciliation: both sources give the same 2-piece ATK bonus and the
    same 5-piece on-field ATK stacking plus Outro Skill DMG bonus. The Prydwen name remains stored in
    each recommendation's `source_name` so the mapping is auditable.
12. Wiki page lookup removes `#` only for the three titles `Broadblade#41`, `Rectifier#25`, and
    `Gauntlets#21D`, because MediaWiki treats `#` as a fragment; the user-facing weapon names retain it.
13. Profile descriptions use the wiki's introductory profile paragraph rather than the promotional
    Official Introduction section. Links, emphasis, references, HTML comments, and line breaks are
    removed mechanically, and whitespace is collapsed. The visible text parameter is retained for
    the wiki `W`, `Extra Effect`, `Rubi`, and `Quest` templates. Wording is not translated or rewritten.
14. The four Rover variants share the descriptive paragraph from the main Rover wiki page. Their
    Level 90 stats remain variant-specific.
15. Level 90 stats are deterministically calculated from the wiki data module with the same published
    multipliers used by its table renderer: `12.5` for HP and ATK and `12.222` for DEF, rounded to two
    decimal places. This calculation is application-generated; the base values and formula are wiki data.
16. Rover uses the Wiki's `Resonator Outfit Perpetual Spark.png` as `icon.png` in the character list
    and `Rover 1.png` as `full_sprite.png` in the profile. The repository field names and filenames are
    application conventions. The Wiki CDN returned the icon as WebP despite its PNG file title, so it
    was decoded and re-encoded as a real PNG without cropping, retouching, generation, or other visual
    edits. The Full Sprites file was copied as PNG.
17. The primary Echo is the first Main Echo option displayed under Prydwen's first ranked Echo Set.
    This selection rule is application-authored; the name and order remain source data.

No machine translation, manually authored translation, generated description, or rewritten profile
text is included.

## Known source limitations

The verified wiki pages did not publish a profile description for Jingran or Suoming. The verified
wiki stats module did not publish complete base HP, ATK, and DEF for Buling, Hsin, Jingran, Lucilla,
Lucy, Rebecca, or Suoming. Those fields are omitted rather than estimated or copied from another site.

Future enrichment must cite a source per added field group and must not silently fill missing
values with guesses, generated prose, or unofficial translations.

Prydwen displayed complete build recommendations for 57 of the 60 roster entries on 2026-08-30.
Hsin, Jingran, and Suoming had no visible weapon or Echo Set recommendations, so no guide record was
created for them. Other characters retain fewer than five weapon entries when Prydwen displayed fewer.

The Wiki pages for Calamity Effigy and Jué reference icon filenames that the Wiki file API does not
currently provide. Their Echo records and provenance are retained with `icon: null`; no Prydwen image,
generated image, or guessed substitute is used.

The wiki API returned exact 404x560 PNG Convene Draw files for 53 roster entries. It did not return
such a file for Hsin, Jingran, or Suoming. Rover is not represented by a character Convene Draw
file, so the four element-specific records use the exact Wiki list icon and Full Sprites described
above instead. No generated image or rewritten artwork is used.
