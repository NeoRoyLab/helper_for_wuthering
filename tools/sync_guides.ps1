$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = [System.Text.UTF8Encoding]::new($false)
$snapshotPath = Join-Path $PSScriptRoot 'prydwen_guide_snapshot.json'

function Read-Json([string] $path) {
    return [System.IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json
}

function Write-Json([string] $path, [object] $value) {
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path)) | Out-Null
    $json = $value | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, $utf8)
}

function Get-StableId([string] $value) {
    $normalized = $value.Normalize([Text.NormalizationForm]::FormD)
    $normalized = [regex]::Replace($normalized, '\p{Mn}', '').Normalize([Text.NormalizationForm]::FormC)
    $normalized = $normalized.ToLowerInvariant().Replace('&', ' and ').Replace("'", '')
    $normalized = [regex]::Replace($normalized, '[^a-z0-9]+', '_').Trim('_')
    if ($normalized -cnotmatch '^[a-z0-9]+(?:_[a-z0-9]+)*$') {
        throw "Could not create a stable id for '$value'."
    }
    return $normalized
}

function Get-TemplateValue([string] $wikitext, [string] $field) {
    $pattern = '(?m)^\s*\|\s*' + [regex]::Escape($field) + '\s*=\s*(.*?)\s*$'
    $match = [regex]::Match($wikitext, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Convert-WikiTextToPlain([string] $value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $text = $value
    $text = [regex]::Replace($text, '\{\{Color\|\s*(.*?)\|\s*nobold\s*=\s*1\s*\}\}', '$1', 'Singleline')
    $text = [regex]::Replace($text, '\[\[([^\]|]+)\|([^\]]+)\]\]', '$2')
    $text = [regex]::Replace($text, '\[\[([^\]]+)\]\]', '$1')
    $text = [regex]::Replace($text, '<br\s*/?>', ' ', 'IgnoreCase')
    $text = [regex]::Replace($text, '<[^>]+>', '')
    $text = $text.Replace("'''", '').Replace("''", '')
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = $text.Replace([string][char]0x00AD, '')
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    if ($text -match '\{\{|\}\}|\[\[|\]\]|<[^>]+>') {
        throw "Unsupported wiki markup remained after conversion: $text"
    }
    return $text
}

function Get-PngDimensions([byte[]] $bytes) {
    if ($bytes.Length -lt 24 -or
        $bytes[0] -ne 137 -or $bytes[1] -ne 80 -or $bytes[2] -ne 78 -or $bytes[3] -ne 71 -or
        $bytes[4] -ne 13 -or $bytes[5] -ne 10 -or $bytes[6] -ne 26 -or $bytes[7] -ne 10) {
        throw 'Downloaded file is not a PNG.'
    }
    $width = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
    $height = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
    return [PSCustomObject]@{ width = $width; height = $height }
}

function Invoke-WikiApi([string] $query) {
    $url = 'https://wutheringwaves.fandom.com/api.php?' + $query
    $json = & curl.exe -L --fail --silent --show-error $url
    if ($LASTEXITCODE -ne 0) { throw 'The Wuthering Waves Wiki API request failed.' }
    return $json | ConvertFrom-Json
}

function Get-WikiPages([string[]] $titles) {
    $result = @{}
    for ($start = 0; $start -lt $titles.Count; $start += 40) {
        $end = [Math]::Min($start + 39, $titles.Count - 1)
        $batch = @($titles[$start..$end])
        $encoded = [Uri]::EscapeDataString(($batch -join '|'))
        $response = Invoke-WikiApi "action=query&format=json&formatversion=2&redirects=1&prop=revisions&rvprop=ids%7Ccontent&rvslots=main&titles=$encoded"
        foreach ($page in $response.query.pages) {
            if ($page.missing) { throw "Wiki page is missing: $($page.title)" }
            $result[[string]$page.title] = $page
        }
        if ($null -ne $response.query.redirects) {
            foreach ($redirect in $response.query.redirects) {
                if ($result.ContainsKey([string]$redirect.to)) {
                    $result[[string]$redirect.from] = $result[[string]$redirect.to]
                }
            }
        }
    }
    foreach ($title in $titles) {
        if (-not $result.ContainsKey($title)) { throw "Wiki response omitted page: $title" }
    }
    return $result
}

function Get-WikiImageInfo([string[]] $fileNames, [bool] $allowMissing = $false) {
    $result = @{}
    $titles = @($fileNames | ForEach-Object { 'File:' + $_ })
    for ($start = 0; $start -lt $titles.Count; $start += 40) {
        $end = [Math]::Min($start + 39, $titles.Count - 1)
        $batch = @($titles[$start..$end])
        $encoded = [Uri]::EscapeDataString(($batch -join '|'))
        $response = Invoke-WikiApi "action=query&format=json&formatversion=2&redirects=1&prop=imageinfo&iiprop=url%7Csize%7Cmime&titles=$encoded"
        foreach ($page in $response.query.pages) {
            if ($page.missing -or $null -eq $page.imageinfo -or $page.imageinfo.Count -ne 1) {
                if ($allowMissing) { continue }
                throw "Wiki image is missing: $($page.title)"
            }
            $result[[string]$page.title] = $page.imageinfo[0]
        }
        if ($null -ne $response.query.redirects) {
            foreach ($redirect in $response.query.redirects) {
                if ($result.ContainsKey([string]$redirect.to)) {
                    $result[[string]$redirect.from] = $result[[string]$redirect.to]
                }
            }
        }
    }
    foreach ($title in $titles) {
        if (-not $result.ContainsKey($title) -and -not $allowMissing) { throw "Wiki response omitted image: $title" }
    }
    return $result
}

function Get-WikiPageUrl([string] $title) {
    return 'https://wutheringwaves.fandom.com/wiki/' + [Uri]::EscapeDataString($title).Replace('%20', '_')
}

function Get-EchoSetWikiName([string] $prydwenName) {
    if ($prydwenName -ceq 'Endless Resonance') { return 'Lingering Tunes' }
    return $prydwenName
}

$snapshot = Read-Json $snapshotPath
if ($snapshot.schema_version -ne 2 -or $snapshot.guides.Count -ne 57) {
    throw 'Unexpected Prydwen guide snapshot.'
}

$characterManifest = Read-Json (Join-Path $root 'manifests\characters.json')
$characterIds = @($characterManifest.characters)
foreach ($guide in $snapshot.guides) {
    if ($guide.id -notin $characterIds) { throw "Unknown character guide id: $($guide.id)" }
    if ($guide.weapons.Count -lt 1 -or $guide.weapons.Count -gt 5) { throw "Invalid weapon count: $($guide.id)" }
    if ($guide.echo_sets.Count -lt 1 -or $guide.main_stats.Count -ne 5 -or
        [string]::IsNullOrWhiteSpace($guide.substats)) { throw "Incomplete build recommendations: $($guide.id)" }
}

$weaponNames = @($snapshot.guides | ForEach-Object { $_.weapons | ForEach-Object { [string]$_[0] } } | Sort-Object -Unique)
$echoSetNames = @($snapshot.guides | ForEach-Object { $_.echo_sets | ForEach-Object { [string]$_.name } } | Sort-Object -Unique)
$echoNames = @($snapshot.guides | ForEach-Object { $_.echo_sets | ForEach-Object { $_.main_echoes } } | Sort-Object -Unique)
if ($weaponNames.Count -ne 82 -or $echoSetNames.Count -ne 33 -or $echoNames.Count -ne 44) {
    throw "Unexpected content counts: $($weaponNames.Count) weapons, $($echoSetNames.Count) Echo Sets."
}

Write-Host "Reading $($weaponNames.Count) weapon pages, $($echoSetNames.Count) Echo Set pages, and $($echoNames.Count) Echo pages from the wiki API..."
$weaponPageTitles = @($weaponNames | ForEach-Object { $_.Replace('#', '') })
$weaponPages = Get-WikiPages $weaponPageTitles
$echoSetPageTitles = @($echoSetNames | ForEach-Object { Get-EchoSetWikiName $_ })
$echoSetPages = Get-WikiPages $echoSetPageTitles
$echoPages = Get-WikiPages $echoNames

$weaponContent = @{}
$echoSetContent = @{}
$echoContent = @{}
$imageFileNames = New-Object System.Collections.Generic.List[string]
$echoImageFileNames = New-Object System.Collections.Generic.List[string]

foreach ($requestedName in $weaponNames) {
    $wikiLookupTitle = $requestedName.Replace('#', '')
    $page = $weaponPages[$wikiLookupTitle]
    $wikitext = [string]$page.revisions[0].slots.main.content
    $canonicalName = Convert-WikiTextToPlain (Get-TemplateValue $wikitext 'name')
    if ([string]::IsNullOrWhiteSpace($canonicalName)) { $canonicalName = $requestedName }
    $image = Get-TemplateValue $wikitext 'image'
    $rarityText = Get-TemplateValue $wikitext 'rarity'
    $weaponType = Get-TemplateValue $wikitext 'type'
    if ([string]::IsNullOrWhiteSpace($canonicalName) -or [string]::IsNullOrWhiteSpace($image) -or
        $rarityText -notmatch '^[1-5]$' -or [string]::IsNullOrWhiteSpace($weaponType)) {
        throw "Incomplete weapon infobox: $requestedName"
    }
    if ($canonicalName -cne $requestedName) { throw "Weapon name mismatch: '$requestedName' vs '$canonicalName'" }
    $id = Get-StableId $canonicalName
    if ($weaponContent.ContainsKey($id)) { throw "Duplicate weapon id: $id" }
    $imageFileNames.Add($image)
    $weaponContent[$id] = [PSCustomObject][ordered]@{
        id = $id
        name = $canonicalName
        rarity = [int]$rarityText
        weapon_type = $weaponType.ToLowerInvariant()
        image_file = $image
        page_title = [string]$page.title
        revision_id = [int]$page.revisions[0].revid
    }
}

foreach ($requestedName in $echoNames) {
    $page = $echoPages[$requestedName]
    $wikitext = [string]$page.revisions[0].slots.main.content
    $canonicalName = Convert-WikiTextToPlain (Get-TemplateValue $wikitext 'name')
    $image = Get-TemplateValue $wikitext 'image'
    if ([string]::IsNullOrWhiteSpace($canonicalName)) { $canonicalName = [string]$page.title }
    if ($canonicalName -cne $requestedName -or [string]::IsNullOrWhiteSpace($image)) {
        throw "Incomplete or mismatched Echo infobox: '$requestedName' vs '$canonicalName'"
    }
    $id = Get-StableId $canonicalName
    if ($echoContent.ContainsKey($id)) { throw "Duplicate Echo id: $id" }
    $echoImageFileNames.Add($image)
    $echoContent[$id] = [PSCustomObject][ordered]@{
        id = $id
        name = $canonicalName
        image_file = $image
        page_title = [string]$page.title
        revision_id = [int]$page.revisions[0].revid
    }
}

foreach ($requestedName in $echoSetNames) {
    $wikiLookupTitle = Get-EchoSetWikiName $requestedName
    $page = $echoSetPages[$wikiLookupTitle]
    $wikitext = [string]$page.revisions[0].slots.main.content
    $canonicalName = Convert-WikiTextToPlain (Get-TemplateValue $wikitext 'title')
    $image = Get-TemplateValue $wikitext 'image'
    if ([string]::IsNullOrWhiteSpace($canonicalName) -or [string]::IsNullOrWhiteSpace($image)) {
        throw "Incomplete Echo Set infobox: $requestedName"
    }
    if ($canonicalName -cne $wikiLookupTitle) { throw "Echo Set name mismatch: '$wikiLookupTitle' vs '$canonicalName'" }
    $bonuses = New-Object System.Collections.Generic.List[object]
    foreach ($pieceCount in @(1, 2, 3, 5)) {
        $raw = Get-TemplateValue $wikitext ($pieceCount.ToString() + 'pc')
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $bonuses.Add([PSCustomObject][ordered]@{
                pieces = $pieceCount
                text = Convert-WikiTextToPlain $raw
            })
        }
    }
    if ($bonuses.Count -eq 0) { throw "Echo Set has no supported piece bonus: $requestedName" }
    $id = Get-StableId $canonicalName
    if ($echoSetContent.ContainsKey($id)) { throw "Duplicate Echo Set id: $id" }
    $imageFileNames.Add($image)
    $echoSetContent[$id] = [PSCustomObject][ordered]@{
        id = $id
        name = $canonicalName
        bonuses = $bonuses.ToArray()
        image_file = $image
        page_title = [string]$page.title
        revision_id = [int]$page.revisions[0].revid
    }
}

$imageInfo = Get-WikiImageInfo @($imageFileNames | Sort-Object -Unique)
$optionalEchoImageInfo = Get-WikiImageInfo @($echoImageFileNames | Sort-Object -Unique) $true
foreach ($key in $optionalEchoImageInfo.Keys) { $imageInfo[$key] = $optionalEchoImageInfo[$key] }
$totalImageCount = $imageInfo.Count
$assetManifest = New-Object System.Collections.Generic.List[object]
$downloaded = 0

foreach ($weapon in @($weaponContent.Values | Sort-Object id)) {
    $relativeIconPath = "weapons/$($weapon.id)/icon.png"
    $target = Join-Path $root ($relativeIconPath.Replace('/', '\'))
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target)) | Out-Null
    $info = $imageInfo['File:' + $weapon.image_file]
    if ($info.mime -cne 'image/png') { throw "Weapon wiki asset is not PNG: $($weapon.name)" }
    $downloadUrl = [string]$info.url + $(if ([string]$info.url -match '\?') { '&format=original' } else { '?format=original' })
    & curl.exe -L --fail --silent --show-error --output $target $downloadUrl
    if ($LASTEXITCODE -ne 0) { throw "Weapon icon download failed: $($weapon.name)" }
    $bytes = [System.IO.File]::ReadAllBytes($target)
    $dimensions = Get-PngDimensions $bytes
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    $source = [PSCustomObject][ordered]@{
        site = 'Wuthering Waves Wiki'
        page_url = Get-WikiPageUrl $weapon.page_title
        verified_at = [string]$snapshot.verified_at
        revision_id = $weapon.revision_id
    }
    $record = [PSCustomObject][ordered]@{
        schema_version = 1
        id = $weapon.id
        name = [PSCustomObject][ordered]@{ en = $weapon.name }
        rarity = $weapon.rarity
        weapon_type = $weapon.weapon_type
        icon = $relativeIconPath
        source = $source
    }
    Write-Json (Join-Path $root "weapons\$($weapon.id)\data.json") $record
    $assetManifest.Add([PSCustomObject][ordered]@{
        kind = 'weapon'
        id = $weapon.id
        path = $relativeIconPath
        wiki_file = $weapon.image_file
        width = $dimensions.width
        height = $dimensions.height
        sha256 = $sha256
    })
    $downloaded++
    if ($downloaded % 10 -eq 0) { Write-Host "Downloaded $downloaded/$totalImageCount wiki PNG assets..." }
}

foreach ($echoSet in @($echoSetContent.Values | Sort-Object id)) {
    $relativeIconPath = "echo_sets/$($echoSet.id)/icon.png"
    $target = Join-Path $root ($relativeIconPath.Replace('/', '\'))
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target)) | Out-Null
    $info = $imageInfo['File:' + $echoSet.image_file]
    if ($info.mime -cne 'image/png') { throw "Echo Set wiki asset is not PNG: $($echoSet.name)" }
    $downloadUrl = [string]$info.url + $(if ([string]$info.url -match '\?') { '&format=original' } else { '?format=original' })
    & curl.exe -L --fail --silent --show-error --output $target $downloadUrl
    if ($LASTEXITCODE -ne 0) { throw "Echo Set icon download failed: $($echoSet.name)" }
    $bytes = [System.IO.File]::ReadAllBytes($target)
    $dimensions = Get-PngDimensions $bytes
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    $source = [PSCustomObject][ordered]@{
        site = 'Wuthering Waves Wiki'
        page_url = Get-WikiPageUrl $echoSet.page_title
        verified_at = [string]$snapshot.verified_at
        revision_id = $echoSet.revision_id
    }
    $record = [PSCustomObject][ordered]@{
        schema_version = 1
        id = $echoSet.id
        name = [PSCustomObject][ordered]@{ en = $echoSet.name }
        bonuses = $echoSet.bonuses
        icon = $relativeIconPath
        source = $source
    }
    Write-Json (Join-Path $root "echo_sets\$($echoSet.id)\data.json") $record
    $assetManifest.Add([PSCustomObject][ordered]@{
        kind = 'echo_set'
        id = $echoSet.id
        path = $relativeIconPath
        wiki_file = $echoSet.image_file
        width = $dimensions.width
        height = $dimensions.height
        sha256 = $sha256
    })
    $downloaded++
    if ($downloaded % 10 -eq 0) { Write-Host "Downloaded $downloaded/$totalImageCount wiki PNG assets..." }
}

foreach ($echo in @($echoContent.Values | Sort-Object id)) {
    $relativeIconPath = "echoes/$($echo.id)/icon.png"
    $target = Join-Path $root ($relativeIconPath.Replace('/', '\'))
    $info = $imageInfo['File:' + $echo.image_file]
    $usesExistingFallback = $echo.name -ceq 'Calamity Effigy' -and $null -eq $info -and (Test-Path -LiteralPath $target)
    $hasIcon = $null -ne $info -or $usesExistingFallback
    if ($null -ne $info -and $info.mime -cne 'image/png') { throw "Echo wiki asset is not PNG: $($echo.name)" }
    if ($hasIcon) {
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target)) | Out-Null
    }
    $downloadUrl = [string]$info.url + $(if ([string]$info.url -match '\?') { '&format=original' } else { '?format=original' })
    if ($hasIcon -and -not $usesExistingFallback) {
        & curl.exe -L --fail --silent --show-error --output $target $downloadUrl
        if ($LASTEXITCODE -ne 0) { throw "Echo icon download failed: $($echo.name)" }
    }
    if ($hasIcon) {
        $bytes = [System.IO.File]::ReadAllBytes($target)
        $dimensions = Get-PngDimensions $bytes
        $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    }
    $record = [PSCustomObject][ordered]@{
        schema_version = 1
        id = $echo.id
        name = [PSCustomObject][ordered]@{ en = $echo.name }
        icon = $(if ($hasIcon) { $relativeIconPath } else { $null })
        source = [PSCustomObject][ordered]@{
            site = 'Wuthering Waves Wiki'
            page_url = Get-WikiPageUrl $echo.page_title
            verified_at = [string]$snapshot.verified_at
            revision_id = $echo.revision_id
        }
    }
    Write-Json (Join-Path $root "echoes\$($echo.id)\data.json") $record
    if ($hasIcon) {
        $assetManifest.Add([PSCustomObject][ordered]@{
            kind = 'echo'
            id = $echo.id
            path = $relativeIconPath
            wiki_file = $echo.image_file
            width = $dimensions.width
            height = $dimensions.height
            sha256 = $sha256
        })
    }
    $downloaded++
    if ($downloaded % 10 -eq 0) { Write-Host "Downloaded $downloaded/$totalImageCount wiki PNG assets..." }
}

$guideIds = New-Object System.Collections.Generic.List[string]
foreach ($guide in $snapshot.guides) {
    $weaponRefs = New-Object System.Collections.Generic.List[object]
    foreach ($weaponRecommendation in $guide.weapons) {
        $contentId = Get-StableId ([string]$weaponRecommendation[0])
        if (-not $weaponContent.ContainsKey($contentId)) { throw "Unknown weapon content id: $contentId" }
        $weaponRefs.Add([PSCustomObject][ordered]@{
            content_id = $contentId
            rank = [int]$weaponRecommendation[1]
        })
    }
    $echoSetRefs = New-Object System.Collections.Generic.List[object]
    foreach ($recommendation in $guide.echo_sets) {
        $echoSetWikiName = Get-EchoSetWikiName ([string]$recommendation.name)
        $echoSetId = Get-StableId $echoSetWikiName
        if (-not $echoSetContent.ContainsKey($echoSetId)) { throw "Unknown Echo Set content id: $echoSetId" }
        $echoSetRefs.Add([PSCustomObject][ordered]@{
            content_id = $echoSetId
            source_name = [string]$recommendation.name
            rank = $(if ($null -eq $recommendation.rank) { 0 } else { [int]$recommendation.rank })
            special = [bool]$recommendation.special
        })
    }
    $primaryEchoName = [string]$guide.echo_sets[0].main_echoes[0]
    $primaryEchoId = Get-StableId $primaryEchoName
    if (-not $echoContent.ContainsKey($primaryEchoId)) { throw "Unknown primary Echo content id: $primaryEchoId" }
    $sourceSlug = ([string]$guide.id).Replace('_', '-')
    $record = [PSCustomObject][ordered]@{
        schema_version = 2
        character_id = [string]$guide.id
        weapons = $weaponRefs.ToArray()
        echo_sets = $echoSetRefs.ToArray()
        primary_echo_id = $primaryEchoId
        primary_echo_source_name = $primaryEchoName
        main_stats = @($guide.main_stats)
        substats = [string]$guide.substats
        source = [PSCustomObject][ordered]@{
            site = 'Prydwen.gg'
            page_url = "https://www.prydwen.gg/wuthering-waves/characters/$sourceSlug"
            verified_at = [string]$snapshot.verified_at
            page_last_updated = [string]$guide.page_last_updated
        }
    }
    Write-Json (Join-Path $root "guides\$($guide.id)\data.json") $record
    $guideIds.Add([string]$guide.id)
}

$guideManifest = [PSCustomObject][ordered]@{
    schema_version = 1
    guides = $guideIds.ToArray()
    weapons = @($weaponContent.Keys | Sort-Object)
    echo_sets = @($echoSetContent.Keys | Sort-Object)
    echoes = @($echoContent.Keys | Sort-Object)
    unavailable = @($snapshot.unavailable)
}
Write-Json (Join-Path $root 'manifests\guides.json') $guideManifest

$guideAssetManifest = [PSCustomObject][ordered]@{
    schema_version = 1
    source_site = 'Wuthering Waves Wiki'
    verified_at = [string]$snapshot.verified_at
    images = $assetManifest.ToArray()
}
Write-Json (Join-Path $root 'manifests\guide_assets.json') $guideAssetManifest

$master = Read-Json (Join-Path $root 'manifest.json')
$entries = New-Object System.Collections.Generic.List[object]
foreach ($entry in $master.manifests) {
    if ($entry.key -cne 'guides') { $entries.Add($entry) }
}
$entries.Add([PSCustomObject][ordered]@{ key = 'guides'; version = 4; count = $guideIds.Count })
$master.manifests = $entries.ToArray()
Write-Json (Join-Path $root 'manifest.json') $master

"Created $($guideIds.Count) character guides, $($weaponContent.Count) wiki weapon records, $($echoSetContent.Count) wiki Echo Set records, $($echoContent.Count) wiki Echo records, and $($assetManifest.Count) exact PNG assets."
