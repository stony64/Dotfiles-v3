<#
.SYNOPSIS
    v3.1.1: Review-Collector (stable) – FULL/FILES, -Files als CSV, Sekunden-Timestamp, RAW-Write, optional SHA256 meta.

.DESCRIPTION
    Erstellt einen review_dump_YYYYMMDD_HHMMSS.txt im Projekt-Ordner (Standard: _exports).
    Unterstützt zwei Aufrufvarianten:
      - Per Projektname relativ zu BaseRepoRoot (ParameterSet 'Project')
      - Per absolutem Repository-Pfad (ParameterSet 'RepoPath')
	  - Mit -Verbose werden zusätzliche Diagnose-Informationen (Mode, Match-Anzahl, Files-Parsing) ausgegeben.

.EXAMPLE
    # Komplettes Projekt (FULL-Mode) anhand des Projektnamens scannen
    .\Collect-Review.ps1 dotfiles-v3 (-Verbose)

.EXAMPLE
    # Nur bestimmte Dateien/Patterns innerhalb des Projekts (FILES-Mode)
    .\Collect-Review.ps1 dotfiles-v3 -Files "core.sh,home/.bashrc,home/config/*"

.EXAMPLE
    # Repository direkt per Pfad angeben
    .\Collect-Review.ps1 -RepoPath "C:\Development\Repositories\OpenSource\dotfiles-v3"

.EXAMPLE
    # Dump erzeugen und direkt in die Zwischenablage kopieren (mit 10 MB Limit)
    .\Collect-Review.ps1 dotfiles-v3 -CopyToClipboard -ClipboardMaxMB 10

.NOTES
    Requires: PowerShell 7.4+
    ParameterSets:
      - Project: Project (positional 0), BaseRepoRoot, Files, OutputDirName, CopyToClipboard, ClipboardMaxMB, ForceClipboard, IncludeFileHash
      - RepoPath: RepoPath (positional 0), Files, OutputDirName, CopyToClipboard, ClipboardMaxMB, ForceClipboard, IncludeFileHash
#>

[CmdletBinding(DefaultParameterSetName = 'Project')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Project', Position = 0)]
    [string]$Project,

    [Parameter(Mandatory = $true, ParameterSetName = 'RepoPath', Position = 0)]
    [string]$RepoPath,

    [Parameter()]
    [string]$BaseRepoRoot = 'C:\Development\Repositories\OpenSource',

    # CSV: "a.ps1,b.ps1,home/*"
    [Parameter()]
    [string]$Files,

    [Parameter()]
    [string]$OutputDirName = "_exports",

    [Parameter()]
    [switch]$CopyToClipboard,

    [Parameter()]
    [int]$ClipboardMaxMB = 20,

    [Parameter()]
    [switch]$ForceClipboard,

    # Optional: schreibt pro Datei eine SHA256-Zeile in den Dump-Header des jeweiligen File-Blocks
    [Parameter()]
    [switch]$IncludeFileHash
)

$ScriptVersion = '3.1.1'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "Script requires PowerShell 7+. Found: $($PSVersionTable.PSVersion)"
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-ForwardSlash([string]$p) { $p.Replace('\', '/') }

function Resolve-RepoRelativePath([string]$fullName, [string]$root) {
    ConvertTo-ForwardSlash ([System.IO.Path]::GetRelativePath($root, $fullName))
}

function Test-Wildcard([string]$s) { ($s -match '[\*\?]') }

function ConvertFrom-FilesCsv {
    param([string]$FilesCsv)

    if ([string]::IsNullOrWhiteSpace($FilesCsv)) { return @() }

    @($FilesCsv -split '\s*,\s*') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Get-FilesFromPattern {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Pattern
    )

    $patternNorm = (ConvertTo-ForwardSlash $Pattern).TrimStart('/')
    $patternFs = $patternNorm.Replace('/', '\')

    if (-not (Test-Wildcard $patternFs)) {
        $full = Join-Path $RepoRoot $patternFs
        if (Test-Path -LiteralPath $full -PathType Leaf) { return , (Get-Item -LiteralPath $full -Force) }
        return @()
    }

    $parent = Split-Path -Path $patternFs -Parent
    $leaf = Split-Path -Path $patternFs -Leaf

    $searchRoot = if ([string]::IsNullOrWhiteSpace($parent)) { $RepoRoot } else { Join-Path $RepoRoot $parent }
    if (!(Test-Path -LiteralPath $searchRoot -PathType Container)) { return @() }

    Get-ChildItem -LiteralPath $searchRoot -File -Recurse -Force -Include $leaf -ErrorAction SilentlyContinue
}

$TargetDir = switch ($PSCmdlet.ParameterSetName) {
    'RepoPath' { (Resolve-Path -Path $RepoPath).Path }
    'Project' { (Resolve-Path -Path (Join-Path $BaseRepoRoot $Project)).Path }
    default { throw "Unknown ParameterSet: $($PSCmdlet.ParameterSetName)" }
}

$OutDir = Join-Path $TargetDir $OutputDirName
if (!(Test-Path $OutDir)) {
    New-Item $OutDir -ItemType Directory -Force | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile = Join-Path $OutDir "review_dump_$stamp.txt"

$ExcludePatterns = @(
    '/\.git(/|$)',
    '/\.vscode(/|$)',
    '/_exports(/|$)',
    '/tests(/|$)',
    '/LICENSE(\.[^/]+)?$',
    '/review_dump_.*\.txt$',

    #   EXCLUDE: Die offizielle Dokumentation (Markdown)
    '(?i)[\\/]+STYLEGUIDE\.md$',

    # INCLUDE: PROMPT_STYLEGUIDES.txt wird erfasst, da sie hier NICHT gelistet ist.
    # Collector selbst ausschließen (Bindestrich/Unterstrich tolerieren)
    '(?i)collect[-_]review\.ps1$',

    # Binaries/Assets
    '\.(png|jpg|jpeg|gif|webp|pdf|zip|7z|gz|tgz|exe|dll|so|node)$'
)

$CombinedExclude = "($($ExcludePatterns -join '|'))"

Write-Host ""
Write-Host "Scan: $TargetDir" -ForegroundColor Cyan

$FilesNormalized = @(ConvertFrom-FilesCsv -FilesCsv $Files)
$mode = if (@($FilesNormalized).Count -gt 0) { 'FILES' } else { 'FULL' }

Write-Verbose ("Files raw: '{0}'" -f $Files)
Write-Verbose ("FilesNormalized.Count={0}" -f (@($FilesNormalized).Count))

if ($mode -eq 'FILES') {
    $filesList = @()
    foreach ($pattern in $FilesNormalized) {
        $filesList += @(Get-FilesFromPattern -RepoRoot $TargetDir -Pattern $pattern)
    }
}
else {
    $filesList = @(Get-ChildItem -LiteralPath $TargetDir -File -Recurse -Force)
}

$filesList = @(
    $filesList |
    Where-Object { (ConvertTo-ForwardSlash $_.FullName) -notmatch $CombinedExclude } |
    Sort-Object FullName -Unique
)

$matched = @($filesList).Count
Write-Verbose ("Mode: {0}; Matched={1}" -f $mode, $matched)

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sw = [System.IO.StreamWriter]::new($OutputFile, $false, $utf8NoBom, 65536)

# Optional: explizit LF als NewLine, damit Dump konsistent ist (WriteLine nutzt das). [web:402]
$sw.NewLine = "`n"

try {
    $sw.WriteLine("COLLECTOR_VERSION: $ScriptVersion")
    $sw.WriteLine("CODE REVIEW DUMP | SOURCE: $TargetDir | $stamp")
    $sw.WriteLine("MODE: $mode")
    if ($mode -eq "FILES") { $sw.WriteLine("FILES: " + ($FilesNormalized -join ', ')) }
    $sw.WriteLine("EXCLUDES_REGEX: $CombinedExclude")
    $sw.WriteLine("FILE_COUNT: $matched")
    $sw.WriteLine("=" * 70)

    foreach ($f in $filesList) {
        $rel = Resolve-RepoRelativePath -fullName $f.FullName -root $TargetDir

        $sw.WriteLine("-" * 70)
        $sw.WriteLine("### BEGIN FILE: $rel   (DUMP HEADER, NOT PART OF FILE)")
        if ($IncludeFileHash) {
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
            $sw.WriteLine("### FILE_SHA256: $hash   (DUMP META)")
        }
        $sw.WriteLine("-" * 70)

        $content = Get-Content -LiteralPath $f.FullName -Raw
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            # RAW: keine zusätzliche Zeilen-Normalisierung über WriteLine(content)
            $sw.Write($content)
            if (-not $content.EndsWith("`n")) { $sw.WriteLine() }
        }

        $sw.WriteLine("-" * 70)
        $sw.WriteLine("### END FILE: $rel")
        $sw.WriteLine("-" * 70)

        Write-Host ("  [+] {0}" -f $rel) -ForegroundColor Gray
    }
}
finally {
    $sw.Close()
    $sw.Dispose()
}

if ($CopyToClipboard) {
    $sizeBytes = (Get-Item -LiteralPath $OutputFile).Length
    $maxBytes = [int64]$ClipboardMaxMB * 1MB

    if (-not $ForceClipboard -and $sizeBytes -gt $maxBytes) {
        $mb = [math]::Round($sizeBytes / 1MB, 2)
        Write-Warning ("Dump is {0} MB and exceeds ClipboardMaxMB={1} MB. Skipping clipboard (use -ForceClipboard)." -f $mb, $ClipboardMaxMB)
    }
    else {
        Get-Content -LiteralPath $OutputFile -Raw | Set-Clipboard
        Write-Host ""
        Write-Host "Clipboard: content copied." -ForegroundColor Magenta
    }
}

Write-Host ""
Write-Host "Dump created: $OutputFile" -ForegroundColor Green
