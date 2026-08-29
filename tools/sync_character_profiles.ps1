param(
    [string] $VerifiedAt = '2026-08-30'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = [System.Text.UTF8Encoding]::new($false)
$wikiRoot = 'https://wutheringwaves.fandom.com/wiki/'
$apiRoot = 'https://wutheringwaves.fandom.com/api.php'
$userAgent = 'HelperForWutheringDataSync/1.0'
$statsModuleTitle = 'Module:Resonator Ascensions and Stats/data'

function Read-Json([string] $path) {
    return [System.IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json
}

function Format-Json([string] $compactJson) {
    $builder = [System.Text.StringBuilder]::new()
    $indent = 0
    $inString = $false
    $escaped = $false
    for ($index = 0; $index -lt $compactJson.Length; $index++) {
        $character = $compactJson[$index]
        if ($inString) {
            [void]$builder.Append($character)
            if ($escaped) { $escaped = $false }
            elseif ($character -eq '\') { $escaped = $true }
            elseif ($character -eq '"') { $inString = $false }
            continue
        }

        switch ($character) {
            '"' {
                $inString = $true
                [void]$builder.Append($character)
            }
            { $_ -in @('{', '[') } {
                [void]$builder.Append($character)
                $next = $compactJson[$index + 1]
                if (($character -eq '{' -and $next -ne '}') -or
                    ($character -eq '[' -and $next -ne ']')) {
                    $indent++
                    [void]$builder.AppendLine()
                    [void]$builder.Append(' ' * ($indent * 2))
                }
            }
            { $_ -in @('}', ']') } {
                $previous = $compactJson[$index - 1]
                if (($character -eq '}' -and $previous -ne '{') -or
                    ($character -eq ']' -and $previous -ne '[')) {
                    $indent--
                    [void]$builder.AppendLine()
                    [void]$builder.Append(' ' * ($indent * 2))
                }
                [void]$builder.Append($character)
            }
            ',' {
                [void]$builder.Append($character)
                [void]$builder.AppendLine()
                [void]$builder.Append(' ' * ($indent * 2))
            }
            ':' {
                [void]$builder.Append(': ')
            }
            default {
                if (-not [char]::IsWhiteSpace($character)) { [void]$builder.Append($character) }
            }
        }
    }
    return $builder.ToString()
}

function Write-Json([string] $path, [object] $value) {
    $json = Format-Json ($value | ConvertTo-Json -Depth 12 -Compress)
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, $utf8)
}

function Invoke-WikiApi([hashtable] $parameters) {
    $parameters.format = 'json'
    $parameters.formatversion = '2'
    $parameters.origin = '*'
    $query = foreach ($entry in $parameters.GetEnumerator()) {
        [Uri]::EscapeDataString([string]$entry.Key) + '=' + [Uri]::EscapeDataString([string]$entry.Value)
    }
    $uri = $apiRoot + '?' + ($query -join '&')
    return Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = $userAgent }
}

function Get-WikiTitle([string] $id, [string] $displayName) {
    switch ($id) {
        'the_shorekeeper' { return 'Shorekeeper' }
        'yangyang_xuanling' { return 'Yangyang: Xuanling' }
        'rover_aero' { return 'Rover-Aero' }
        'rover_electro' { return 'Rover-Electro' }
        'rover_havoc' { return 'Rover-Havoc' }
        'rover_spectro' { return 'Rover-Spectro' }
        default { return $displayName }
    }
}

function Convert-SimpleTemplate([System.Text.RegularExpressions.Match] $match) {
    $parts = @($match.Groups[1].Value -split '\|')
    $template = $parts[0].Trim().ToLowerInvariant()
    switch ($template) {
        { $_ -in @('w', 'wikipedia') } {
            if ($parts.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($parts[2])) { return $parts[2].Trim() }
            if ($parts.Count -ge 2) { return $parts[1].Trim() }
        }
        'extra effect' {
            if ($parts.Count -ge 2) { return $parts[1].Trim() }
        }
        'rubi' {
            if ($parts.Count -ge 2) { return $parts[1].Trim() }
        }
        'quest' {
            if ($parts.Count -ge 2) { return $parts[1].Trim() }
        }
    }

    throw "Unsupported wiki template in profile description: $($match.Value)"
}

function Convert-WikiTextToPlainText([string] $wikiText) {
    if ([string]::IsNullOrWhiteSpace($wikiText)) { return $null }

    $text = [regex]::Replace($wikiText, '(?s)<!--.*?-->', '')
    $text = [regex]::Replace($text, '(?is)<ref\b[^>]*>.*?</ref\s*>', '')
    $text = [regex]::Replace($text, '(?is)<ref\b[^>]*/\s*>', '')
    while ($text -match '\{\{[^{}]*\}\}') {
        $text = [regex]::Replace($text, '\{\{([^{}]*)\}\}', { param($match) Convert-SimpleTemplate $match })
    }
    if ($text -match '\{\{|\}\}') { throw "Nested wiki template remains in description: $text" }

    $text = [regex]::Replace($text, '\[\[([^\]|]+)\|([^\]]+)\]\]', '$2')
    $text = [regex]::Replace($text, '\[\[([^\]]+)\]\]', '$1')
    $text = [regex]::Replace($text, '\[(?:https?://[^\s\]]+)\s+([^\]]+)\]', '$1')
    $text = [regex]::Replace($text, '\[(?:https?://[^\]]+)\]', '')
    $text = [regex]::Replace($text, '(?i)<br\s*/?>', ' ')
    $text = [regex]::Replace($text, '<[^>]+>', '')
    $text = $text.Replace("'''", '').Replace("''", '')
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = [regex]::Replace($text, '\s+', ' ').Trim()

    if ($text -match '\[\[|\]\]|\{\{|\}\}|<[^>]+>') {
        throw "Wiki markup remains in description: $text"
    }
    return $(if ([string]::IsNullOrWhiteSpace($text)) { $null } else { $text })
}

function Get-ProfileDescription([string] $wikiTitle, [string] $wikiText) {
    if ([string]::IsNullOrWhiteSpace($wikiText)) { return $null }

    if ($wikiTitle.StartsWith('Rover-', [StringComparison]::Ordinal)) {
        return $null
    }

    $visibleWikiText = [regex]::Replace($wikiText, '(?s)<!--.*?-->', '')
    $match = [regex]::Match(
        $visibleWikiText,
        '(?s)\{\{Intro/Resonator[^}]*\}\}(?<description>.*?)(?=\r?\n\s*==|$)')
    if (-not $match.Success) { return $null }
    return Convert-WikiTextToPlainText $match.Groups['description'].Value
}

function Get-RoverDescription([string] $wikiText) {
    $match = [regex]::Match(
        $wikiText,
        "(?s)'''Rover'''[^\r\n]*(?:\r?\n){2}(?<description>.*?)(?=\r?\n\s*==|$)")
    if (-not $match.Success) { return $null }
    return Convert-WikiTextToPlainText $match.Groups['description'].Value
}

function Get-NumberFromStatsBlock([string] $body, [string] $field) {
    $match = [regex]::Match($body, "\['$field'\]\s*=\s*(?<value>nil|\d+(?:\.\d+)?)")
    if (-not $match.Success -or $match.Groups['value'].Value -ceq 'nil') { return $null }
    return [decimal]::Parse($match.Groups['value'].Value, [Globalization.CultureInfo]::InvariantCulture)
}

function Get-LevelNinetyStats([string] $body) {
    $baseHp = Get-NumberFromStatsBlock $body 'base_hp'
    $baseAttack = Get-NumberFromStatsBlock $body 'base_atk'
    $baseDefense = Get-NumberFromStatsBlock $body 'base_def'
    if ($null -eq $baseHp -or $null -eq $baseAttack -or $null -eq $baseDefense) { return $null }

    return [PSCustomObject][ordered]@{
        level = 90
        hp = [Math]::Round($baseHp * [decimal]12.5, 2, [MidpointRounding]::AwayFromZero)
        attack = [Math]::Round($baseAttack * [decimal]12.5, 2, [MidpointRounding]::AwayFromZero)
        defense = [Math]::Round($baseDefense * [decimal]12.222, 2, [MidpointRounding]::AwayFromZero)
    }
}

$statsResponse = Invoke-WikiApi @{
    action = 'parse'
    page = $statsModuleTitle
    prop = 'wikitext|revid'
}
$statsRevision = [int]$statsResponse.parse.revid
$statsWikiText = [string]$statsResponse.parse.wikitext
$statsByTitle = @{}
$entryMatches = [regex]::Matches(
    $statsWikiText,
    "(?ms)^\s*\['(?<title>(?:\\'|[^'])+)'\]\s*=\s*\{(?<body>.*?)^\s*\},")
foreach ($match in $entryMatches) {
    $title = $match.Groups['title'].Value.Replace("\'", "'")
    $statsByTitle[$title] = Get-LevelNinetyStats $match.Groups['body'].Value
}

$characterManifest = Read-Json (Join-Path $root 'manifests\characters.json')
$entries = foreach ($id in $characterManifest.characters) {
    $recordPath = Join-Path $root "characters\$id\data.json"
    $record = Read-Json $recordPath
    [PSCustomObject]@{
        id = [string]$id
        record = $record
        recordPath = $recordPath
        wikiTitle = Get-WikiTitle $id ([string]$record.name.en)
    }
}

$requestedTitles = New-Object System.Collections.Generic.List[string]
foreach ($entry in $entries) {
    $overviewTitle = if ($entry.id.StartsWith('rover_', [StringComparison]::Ordinal)) { 'Rover' } else { $entry.wikiTitle }
    if (-not $requestedTitles.Contains($overviewTitle)) { $requestedTitles.Add($overviewTitle) }
}

$pagesByTitle = @{}
for ($start = 0; $start -lt $requestedTitles.Count; $start += 40) {
    $end = [Math]::Min($start + 39, $requestedTitles.Count - 1)
    $titles = @($requestedTitles[$start..$end]) -join '|'
    $response = Invoke-WikiApi @{
        action = 'query'
        prop = 'revisions'
        rvprop = 'ids|content'
        rvslots = 'main'
        titles = $titles
        redirects = '1'
    }
    foreach ($page in $response.query.pages) {
        $pagesByTitle[[string]$page.title] = $page
    }
}

$profiles = New-Object System.Collections.Generic.List[object]
$unavailable = New-Object System.Collections.Generic.List[object]
$roverPage = $pagesByTitle['Rover']
$roverWikiText = if ($null -ne $roverPage -and $null -ne $roverPage.revisions) {
    [string]$roverPage.revisions[0].slots.main.content
} else { '' }
$roverDescription = Get-RoverDescription $roverWikiText

foreach ($entry in $entries) {
    $overviewTitle = if ($entry.id.StartsWith('rover_', [StringComparison]::Ordinal)) { 'Rover' } else { $entry.wikiTitle }
    $page = $pagesByTitle[$overviewTitle]
    $wikiText = if ($null -ne $page -and $null -ne $page.revisions) {
        [string]$page.revisions[0].slots.main.content
    } else { '' }
    $description = if ($entry.id.StartsWith('rover_', [StringComparison]::Ordinal)) {
        $roverDescription
    } else {
        Get-ProfileDescription $entry.wikiTitle $wikiText
    }
    $stats = $statsByTitle[$entry.wikiTitle]
    $overviewRevision = if ($null -ne $page -and $null -ne $page.revisions) {
        [int]$page.revisions[0].revid
    } else { 0 }

    $missing = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($description)) { $missing.Add('description') }
    if ($null -eq $stats) { $missing.Add('max_level_stats') }

    $profile = $null
    if ($missing.Count -lt 2) {
        $profileValues = [ordered]@{}
        if (-not [string]::IsNullOrWhiteSpace($description)) {
            $profileValues.description = [PSCustomObject][ordered]@{ en = $description }
        }
        if ($null -ne $stats) { $profileValues.max_level_stats = $stats }
        $profileValues.source = [PSCustomObject][ordered]@{
            site = 'Wuthering Waves Wiki'
            page_url = $wikiRoot + [Uri]::EscapeDataString($overviewTitle).Replace('%20', '_')
            verified_at = $VerifiedAt
            overview_revision_id = $overviewRevision
            stats_module_url = $wikiRoot + [Uri]::EscapeDataString($statsModuleTitle).Replace('%20', '_')
            stats_module_revision_id = $statsRevision
        }
        $profile = [PSCustomObject]$profileValues
    }

    $outputValues = [ordered]@{
        schema_version = [int]$entry.record.schema_version
        id = [string]$entry.record.id
        name = $entry.record.name
        rarity = [int]$entry.record.rarity
        element = [string]$entry.record.element
        weapon_type = [string]$entry.record.weapon_type
    }
    if ($null -ne $profile) { $outputValues.profile = $profile }
    $outputValues.source = $entry.record.source
    $outputValues.convene_draw = $entry.record.convene_draw
    Write-Json $entry.recordPath ([PSCustomObject]$outputValues)

    $profiles.Add([PSCustomObject][ordered]@{
        id = $entry.id
        page_url = $wikiRoot + [Uri]::EscapeDataString($overviewTitle).Replace('%20', '_')
        overview_revision_id = $overviewRevision
        has_description = -not [string]::IsNullOrWhiteSpace($description)
        has_max_level_stats = $null -ne $stats
    })
    if ($missing.Count -gt 0) {
        $unavailable.Add([PSCustomObject][ordered]@{
            id = $entry.id
            missing = $missing.ToArray()
            reason = 'The listed field was not published in the verified wiki source.'
        })
    }
}

$profileManifest = [PSCustomObject][ordered]@{
    schema_version = 1
    source_site = 'Wuthering Waves Wiki'
    verified_at = $VerifiedAt
    stats_module_url = $wikiRoot + [Uri]::EscapeDataString($statsModuleTitle).Replace('%20', '_')
    stats_module_revision_id = $statsRevision
    profiles = $profiles.ToArray()
    unavailable = $unavailable.ToArray()
}
Write-Json (Join-Path $root 'manifests\character_profiles.json') $profileManifest

$master = Read-Json (Join-Path $root 'manifest.json')
$charactersEntry = $master.manifests | Where-Object { $_.key -ceq 'characters' } | Select-Object -First 1
if ($null -eq $charactersEntry) { throw 'The master manifest has no characters entry.' }
$charactersEntry.version = 3
Write-Json (Join-Path $root 'manifest.json') $master

$withDescriptions = @($profiles | Where-Object { $_.has_description }).Count
$withStats = @($profiles | Where-Object { $_.has_max_level_stats }).Count
"Updated $($profiles.Count) character records: $withDescriptions descriptions and $withStats Level 90 stat blocks from verified wiki revisions."
