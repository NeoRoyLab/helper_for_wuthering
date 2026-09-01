$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-Json([string] $path) {
    $text = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path))
    return $text | ConvertFrom-Json
}

$master = Read-Json (Join-Path $root 'manifest.json')
$manifest = Read-Json (Join-Path $root 'manifests\characters.json')
$imageManifest = Read-Json (Join-Path $root 'manifests\character_images.json')
$profileManifest = Read-Json (Join-Path $root 'manifests\character_profiles.json')
if ($master.schema_version -ne 1) { throw 'Unexpected master schema version.' }
if ($manifest.schema_version -ne 1) { throw 'Unexpected character manifest schema version.' }
if ($manifest.characters.Count -ne 60) { throw "Expected 60 ids, got $($manifest.characters.Count)." }
if (($manifest.characters | Sort-Object -Unique).Count -ne 60) { throw 'Duplicate manifest ids.' }
$characterEntry = $master.manifests | Where-Object { $_.key -ceq 'characters' } | Select-Object -First 1
if ($null -eq $characterEntry -or $characterEntry.version -ne 4 -or $characterEntry.count -ne 60) {
    throw 'The master manifest characters entry is missing or invalid.'
}

$elements = @('aero', 'electro', 'fusion', 'glacio', 'havoc', 'spectro')
$weapons = @('broadblade', 'gauntlets', 'pistols', 'rectifier', 'sword')
$expectedImageCount = 53
$expectedUnavailableCount = 3
$imageById = @{}
foreach ($image in $imageManifest.images) {
    if ($imageById.ContainsKey([string]$image.id)) { throw "Duplicate image id: $($image.id)" }
    $imageById[[string]$image.id] = $image
}
if ($imageById.Count -ne $expectedImageCount) { throw "Expected $expectedImageCount images, got $($imageById.Count)." }
if ($imageManifest.unavailable.Count -ne $expectedUnavailableCount) { throw "Expected $expectedUnavailableCount unavailable entries." }
$roverIds = @('rover_aero', 'rover_electro', 'rover_havoc', 'rover_spectro')
$roverImageByPath = @{}
foreach ($image in $imageManifest.rover_images) {
    if ($image.role -notin @('list_icon', 'profile_full_sprite') -or
        $roverImageByPath.ContainsKey([string]$image.path)) {
        throw "Invalid or duplicate Rover image: $($image.path)"
    }
    $roverImageByPath[[string]$image.path] = $image
}
if ($roverImageByPath.Count -ne 8) { throw "Expected 8 Rover images, got $($roverImageByPath.Count)." }
$expectedMissingDescriptions = @('jingran', 'suoming')
$expectedMissingStats = @('buling', 'hsin', 'jingran', 'lucilla', 'lucy', 'rebecca', 'suoming')
if ($profileManifest.schema_version -ne 1 -or
    $profileManifest.source_site -cne 'Wuthering Waves Wiki' -or
    $profileManifest.verified_at -cne '2026-08-30' -or
    $profileManifest.stats_module_revision_id -le 0 -or
    $profileManifest.profiles.Count -ne 60 -or
    $profileManifest.unavailable.Count -ne 7) {
    throw 'Invalid character profile manifest metadata.'
}
if (@(Compare-Object $expectedMissingStats @($profileManifest.unavailable.id)).Count -ne 0) {
    throw 'Character profile gaps are not documented exactly.'
}
$profileById = @{}
foreach ($profileIndex in $profileManifest.profiles) {
    if ($profileById.ContainsKey([string]$profileIndex.id)) { throw "Duplicate profile id: $($profileIndex.id)" }
    $profileById[[string]$profileIndex.id] = $profileIndex
}
foreach ($id in $manifest.characters) {
    if ($id -cnotmatch '^[a-z0-9]+(?:_[a-z0-9]+)*$') { throw "Invalid id: $id" }
    $path = Join-Path $root "characters\$id\data.json"
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing record: $id" }
    $record = Read-Json $path
    if ($record.id -cne $id) { throw "Id mismatch: $id" }
    if ([string]::IsNullOrWhiteSpace($record.name.en)) { throw "Missing English name: $id" }
    if ($record.rarity -notin @(4, 5)) { throw "Invalid rarity: $id" }
    if ($record.element -notin $elements) { throw "Invalid element: $id" }
    if ($record.weapon_type -notin $weapons) { throw "Invalid weapon: $id" }
    if ($record.source.site -cne 'Prydwen.gg') { throw "Invalid source: $id" }
    if ($record.source.verified_at -cne '2026-08-28') { throw "Invalid verification date: $id" }

    if (-not $profileById.ContainsKey($id)) { throw "Profile manifest omitted character: $id" }
    $profileIndex = $profileById[$id]
    $hasDescription = $null -ne $record.profile -and
        -not [string]::IsNullOrWhiteSpace([string]$record.profile.description.en)
    $hasStats = $null -ne $record.profile -and $null -ne $record.profile.max_level_stats
    if ($hasDescription -ne [bool]$profileIndex.has_description -or
        $hasStats -ne [bool]$profileIndex.has_max_level_stats) {
        throw "Profile availability mismatch: $id"
    }
    if (($id -in $expectedMissingDescriptions) -eq $hasDescription) {
        throw "Unexpected description availability: $id"
    }
    if (($id -in $expectedMissingStats) -eq $hasStats) {
        throw "Unexpected Level 90 stat availability: $id"
    }
    if ($hasDescription -and [string]$record.profile.description.en -match '\[\[|\]\]|\{\{|\}\}|<[^>]+>') {
        throw "Wiki markup remains in profile description: $id"
    }
    if ($hasStats -and ($record.profile.max_level_stats.level -ne 90 -or
        $record.profile.max_level_stats.hp -le 0 -or
        $record.profile.max_level_stats.attack -le 0 -or
        $record.profile.max_level_stats.defense -le 0)) {
        throw "Invalid Level 90 stats: $id"
    }
    if ($null -ne $record.profile -and ($record.profile.source.site -cne 'Wuthering Waves Wiki' -or
        $record.profile.source.verified_at -cne '2026-08-30' -or
        $record.profile.source.overview_revision_id -le 0 -or
        $record.profile.source.stats_module_revision_id -ne $profileManifest.stats_module_revision_id -or
        [string]::IsNullOrWhiteSpace([string]$record.profile.source.page_url) -or
        [string]::IsNullOrWhiteSpace([string]$record.profile.source.stats_module_url))) {
        throw "Invalid wiki profile provenance: $id"
    }

    if ($imageById.ContainsKey($id)) {
        $image = $imageById[$id]
        $expectedPath = "characters/$id/convene_draw.png"
        if ($record.convene_draw -cne $expectedPath -or $image.path -cne $expectedPath) {
            throw "Invalid Convene Draw path: $id"
        }
        $imagePath = Join-Path $root ($expectedPath.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $imagePath)) { throw "Missing Convene Draw PNG: $id" }
        $bytes = [System.IO.File]::ReadAllBytes($imagePath)
        if ($bytes.Length -lt 24 -or $bytes[0] -ne 137 -or $bytes[1] -ne 80 -or $bytes[2] -ne 78 -or $bytes[3] -ne 71) {
            throw "Invalid PNG signature: $id"
        }
        $width = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
        $height = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
        if ($width -ne 404 -or $height -ne 560 -or $image.width -ne 404 -or $image.height -ne 560) {
            throw "Unexpected PNG dimensions: $id"
        }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $imagePath).Hash.ToLowerInvariant()
        if ($hash -cne $image.sha256) { throw "PNG hash mismatch: $id" }
    }
    elseif ($id -in $roverIds) {
        $expectedIconPath = "characters/$id/icon.png"
        $expectedFullSpritePath = "characters/$id/full_sprite.png"
        if ($null -ne $record.convene_draw -or $record.icon -cne $expectedIconPath -or
            $record.full_sprite -cne $expectedFullSpritePath) {
            throw "Invalid Rover artwork paths: $id"
        }

        foreach ($expected in @(
            @{ Path = $expectedIconPath; Role = 'list_icon'; Width = 256; Height = 256 },
            @{ Path = $expectedFullSpritePath; Role = 'profile_full_sprite'; Width = 1079; Height = 1033 }
        )) {
            if (-not $roverImageByPath.ContainsKey($expected.Path)) {
                throw "Rover artwork omitted from image manifest: $($expected.Path)"
            }
            $image = $roverImageByPath[$expected.Path]
            if ($image.id -cne $id -or $image.role -cne $expected.Role) {
                throw "Invalid Rover artwork metadata: $($expected.Path)"
            }
            $imagePath = Join-Path $root $expected.Path.Replace('/', '\')
            if (-not (Test-Path -LiteralPath $imagePath)) { throw "Missing Rover PNG: $($expected.Path)" }
            $bytes = [System.IO.File]::ReadAllBytes($imagePath)
            if ($bytes.Length -lt 24 -or $bytes[0] -ne 137 -or $bytes[1] -ne 80 -or
                $bytes[2] -ne 78 -or $bytes[3] -ne 71) {
                throw "Invalid Rover PNG signature: $($expected.Path)"
            }
            $width = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
            $height = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $imagePath).Hash.ToLowerInvariant()
            if ($width -ne $expected.Width -or $height -ne $expected.Height -or
                $image.width -ne $expected.Width -or $image.height -ne $expected.Height -or
                $image.sha256 -cne $hash) {
                throw "Rover PNG metadata mismatch: $($expected.Path)"
            }
        }
    }
    elseif ($null -ne $record.convene_draw) {
        throw "Unexpected Convene Draw path for unavailable entry: $id"
    }

    if ($id -notin $roverIds -and ($null -ne $record.icon -or $null -ne $record.full_sprite)) {
        throw "Unexpected alternate character artwork path: $id"
    }
}

$aalto = Read-Json (Join-Path $root 'characters\aalto\data.json')
if ($aalto.profile.max_level_stats.hp -ne 9850 -or
    $aalto.profile.max_level_stats.attack -ne 262.5 -or
    $aalto.profile.max_level_stats.defense -ne 1075.54 -or
    $aalto.profile.description.en -cne 'He is an information broker from the New Federation and a Consultant of the Black Shores.') {
    throw 'Aalto profile does not match the verified wiki values.'
}

$files = @(Get-ChildItem -LiteralPath (Join-Path $root 'characters') -Filter data.json -File -Recurse)
if ($files.Count -ne 60) { throw "Expected 60 records, got $($files.Count)." }

$guideEntry = $master.manifests | Where-Object { $_.key -ceq 'guides' } | Select-Object -First 1
if ($null -eq $guideEntry -or $guideEntry.version -ne 4 -or $guideEntry.count -ne 57) {
    throw 'The master manifest guides entry is missing or invalid.'
}

$guideManifest = Read-Json (Join-Path $root 'manifests\guides.json')
$guideAssetManifest = Read-Json (Join-Path $root 'manifests\guide_assets.json')
if ($guideManifest.schema_version -ne 1 -or $guideAssetManifest.schema_version -ne 1) {
    throw 'Unexpected guide manifest schema version.'
}
if ($guideManifest.guides.Count -ne 57 -or $guideManifest.weapons.Count -ne 82 -or
    $guideManifest.echo_sets.Count -ne 33 -or $guideManifest.echoes.Count -ne 44) {
    throw 'Unexpected guide, weapon, Echo Set, or Echo manifest count.'
}
if (($guideManifest.guides | Sort-Object -Unique).Count -ne 57 -or
    ($guideManifest.weapons | Sort-Object -Unique).Count -ne 82 -or
    ($guideManifest.echo_sets | Sort-Object -Unique).Count -ne 33 -or
    ($guideManifest.echoes | Sort-Object -Unique).Count -ne 44) {
    throw 'Duplicate guide content identifier.'
}
$expectedGuideGaps = @('hsin', 'jingran', 'suoming')
if ($guideManifest.unavailable.Count -ne 3 -or
    @(Compare-Object $expectedGuideGaps @($guideManifest.unavailable.id)).Count -ne 0) {
    throw 'The Prydwen guide gaps are not documented exactly.'
}

$guideWeaponById = @{}
foreach ($id in $guideManifest.weapons) {
    if ($id -cnotmatch '^[a-z0-9]+(?:_[a-z0-9]+)*$') { throw "Invalid weapon content id: $id" }
    $recordPath = Join-Path $root "weapons\$id\data.json"
    if (-not (Test-Path -LiteralPath $recordPath)) { throw "Missing weapon content record: $id" }
    $record = Read-Json $recordPath
    if ($record.schema_version -ne 1 -or $record.id -cne $id -or [string]::IsNullOrWhiteSpace($record.name.en)) {
        throw "Invalid weapon content record: $id"
    }
    if ($record.rarity -notin @(3, 4, 5) -or $record.weapon_type -notin $weapons) {
        throw "Invalid wiki weapon metadata: $id"
    }
    $expectedPath = "weapons/$id/icon.png"
    if ($record.icon -cne $expectedPath -or $record.source.site -cne 'Wuthering Waves Wiki' -or
        $record.source.verified_at -cne '2026-08-30' -or $record.source.revision_id -le 0 -or
        $record.source.page_url -notlike 'https://wutheringwaves.fandom.com/wiki/*') {
        throw "Invalid weapon provenance or icon path: $id"
    }
    $guideWeaponById[$id] = $record
}

$echoSetById = @{}
foreach ($id in $guideManifest.echo_sets) {
    if ($id -cnotmatch '^[a-z0-9]+(?:_[a-z0-9]+)*$') { throw "Invalid Echo Set content id: $id" }
    $recordPath = Join-Path $root "echo_sets\$id\data.json"
    if (-not (Test-Path -LiteralPath $recordPath)) { throw "Missing Echo Set content record: $id" }
    $record = Read-Json $recordPath
    if ($record.schema_version -ne 1 -or $record.id -cne $id -or [string]::IsNullOrWhiteSpace($record.name.en)) {
        throw "Invalid Echo Set content record: $id"
    }
    if ($record.bonuses.Count -lt 1 -or ($record.bonuses.pieces | Sort-Object -Unique).Count -ne $record.bonuses.Count) {
        throw "Invalid Echo Set bonus list: $id"
    }
    foreach ($bonus in $record.bonuses) {
        if ($bonus.pieces -notin @(1, 2, 3, 5) -or [string]::IsNullOrWhiteSpace($bonus.text) -or
            $bonus.text -match '\{\{|\}\}|\[\[|\]\]|<[^>]+>') {
            throw "Invalid plain-text Echo Set bonus: $id"
        }
    }
    $expectedPath = "echo_sets/$id/icon.png"
    if ($record.icon -cne $expectedPath -or $record.source.site -cne 'Wuthering Waves Wiki' -or
        $record.source.verified_at -cne '2026-08-30' -or $record.source.revision_id -le 0 -or
        $record.source.page_url -notlike 'https://wutheringwaves.fandom.com/wiki/*') {
        throw "Invalid Echo Set provenance or icon path: $id"
    }
    $echoSetById[$id] = $record
}

$echoById = @{}
$expectedEchoIconGaps = @('jue')
foreach ($id in $guideManifest.echoes) {
    $recordPath = Join-Path $root "echoes\$id\data.json"
    if (-not (Test-Path -LiteralPath $recordPath)) { throw "Missing Echo content record: $id" }
    $record = Read-Json $recordPath
    if ($record.schema_version -ne 1 -or $record.id -cne $id -or [string]::IsNullOrWhiteSpace($record.name.en) -or
        $record.source.site -cne 'Wuthering Waves Wiki' -or $record.source.verified_at -cne '2026-08-30' -or
        $record.source.revision_id -le 0 -or $record.source.page_url -notlike 'https://wutheringwaves.fandom.com/wiki/*') {
        throw "Invalid Echo content record: $id"
    }
    $expectedPath = "echoes/$id/icon.png"
    if ($id -in $expectedEchoIconGaps) {
        if ($null -ne $record.icon) { throw "Unexpected icon for documented Wiki file gap: $id" }
    }
    elseif ($record.icon -cne $expectedPath) {
        throw "Invalid Echo icon path: $id"
    }
    $echoById[$id] = $record
}

foreach ($id in $guideManifest.guides) {
    if ($id -notin $manifest.characters) { throw "Guide references an unknown character: $id" }
    $recordPath = Join-Path $root "guides\$id\data.json"
    if (-not (Test-Path -LiteralPath $recordPath)) { throw "Missing guide record: $id" }
    $record = Read-Json $recordPath
    if ($record.schema_version -ne 2 -or $record.character_id -cne $id -or
        $record.weapons.Count -lt 1 -or $record.weapons.Count -gt 5 -or
        $record.echo_sets.Count -lt 1 -or $record.main_stats.Count -ne 5 -or
        [string]::IsNullOrWhiteSpace($record.substats)) {
        throw "Invalid guide record: $id"
    }
    foreach ($weapon in $record.weapons) {
        if (-not $guideWeaponById.ContainsKey([string]$weapon.content_id) -or $weapon.rank -lt 1 -or $weapon.rank -gt 5) {
            throw "Invalid guide weapon reference: $id"
        }
    }
    foreach ($echoSet in $record.echo_sets) {
        if (-not $echoSetById.ContainsKey([string]$echoSet.content_id) -or $echoSet.rank -lt 0) {
            throw "Invalid guide Echo Set reference: $id"
        }
        $wikiEchoName = [string]$echoSetById[[string]$echoSet.content_id].name.en
        if ($echoSet.source_name -cne $wikiEchoName -and
            -not ($echoSet.source_name -ceq 'Endless Resonance' -and $wikiEchoName -ceq 'Lingering Tunes')) {
            throw "Undocumented Prydwen/wiki Echo Set name mismatch: $id"
        }
    }
    if (-not $echoById.ContainsKey([string]$record.primary_echo_id) -or
        $record.primary_echo_source_name -cne $echoById[[string]$record.primary_echo_id].name.en) {
        throw "Invalid guide primary Echo reference: $id"
    }
    foreach ($stat in $record.main_stats) {
        if ($stat.cost -notin @(1, 3, 4) -or [string]::IsNullOrWhiteSpace($stat.value)) {
            throw "Invalid guide main stat: $id"
        }
    }
    $expectedSourceUrl = 'https://www.prydwen.gg/wuthering-waves/characters/' + $id.Replace('_', '-')
    if ($record.source.site -cne 'Prydwen.gg' -or $record.source.page_url -cne $expectedSourceUrl -or
        $record.source.verified_at -cne '2026-08-30' -or $record.source.page_last_updated -notmatch '^2026-\d{2}-\d{2}$') {
        throw "Invalid guide provenance: $id"
    }
}

if ($guideAssetManifest.source_site -cne 'Wuthering Waves Wiki' -or
    $guideAssetManifest.verified_at -cne '2026-08-30' -or $guideAssetManifest.images.Count -ne 158) {
    throw 'Invalid guide asset manifest metadata.'
}
$assetByPath = @{}
foreach ($asset in $guideAssetManifest.images) {
    if ($asset.kind -notin @('weapon', 'echo_set', 'echo') -or $assetByPath.ContainsKey([string]$asset.path)) {
        throw "Invalid or duplicate guide asset: $($asset.path)"
    }
    $assetByPath[[string]$asset.path] = $asset
    $path = Join-Path $root ([string]$asset.path).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing guide PNG: $($asset.path)" }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 24 -or $bytes[0] -ne 137 -or $bytes[1] -ne 80 -or $bytes[2] -ne 78 -or $bytes[3] -ne 71) {
        throw "Invalid guide PNG signature: $($asset.path)"
    }
    $width = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
    $height = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($asset.width -ne $width -or $asset.height -ne $height -or $asset.sha256 -cne $hash) {
        throw "Guide PNG metadata mismatch: $($asset.path)"
    }
}

foreach ($record in $guideWeaponById.Values) {
    if (-not $assetByPath.ContainsKey([string]$record.icon)) { throw "Weapon icon omitted from asset manifest: $($record.id)" }
}
foreach ($record in $echoSetById.Values) {
    if (-not $assetByPath.ContainsKey([string]$record.icon)) { throw "Echo Set icon omitted from asset manifest: $($record.id)" }
}
foreach ($record in $echoById.Values) {
    if ($null -ne $record.icon -and -not $assetByPath.ContainsKey([string]$record.icon)) {
        throw "Echo icon omitted from asset manifest: $($record.id)"
    }
}

$guideFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'guides') -Filter data.json -File -Recurse)
$weaponFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'weapons') -Filter data.json -File -Recurse)
$echoSetFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'echo_sets') -Filter data.json -File -Recurse)
$echoFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'echoes') -Filter data.json -File -Recurse)
if ($guideFiles.Count -ne 57 -or $weaponFiles.Count -ne 84 -or $echoSetFiles.Count -ne 33 -or $echoFiles.Count -ne 44) {
    throw 'Unexpected generated guide content file count.'
}

"Validated 60 character records, 58 wiki descriptions, 53 wiki Level 90 stat blocks, $($expectedImageCount + $roverImageByPath.Count) character PNGs, 57 complete guides, 82 referenced wiki weapon records, 33 wiki Echo Sets, 44 wiki Echoes, 158 exact guide PNGs, documented gaps, provenance, references, hashes, and strict UTF-8."
