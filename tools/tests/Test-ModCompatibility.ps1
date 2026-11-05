$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ets2-compat-test-' + [guid]::NewGuid().ToString('N'))
$tools = Join-Path $root 'tools'
$mods = Join-Path $root 'mod'
$profileRoot = Join-Path $root 'profile'
$backupRoot = Join-Path $root 'backups'
New-Item -ItemType Directory -Path $tools,$mods,$profileRoot | Out-Null
$oldTestVersion = $env:ETS2_COMPAT_TEST_VERSION
$oldTestLock = $env:ETS2_COMPAT_TEST_LOCK
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../Update-ModCompatibility.ps1'),(Join-Path $PSScriptRoot '../CompatibilityPatch.cs') -Destination $tools
    @'
function Get-Ets2InstallPath { return $null }
function Get-Ets2LogInfo { [pscustomobject]@{ GameVersion = $env:ETS2_COMPAT_TEST_VERSION } }
function Get-FileSha256([string]$Path) {
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($env:ETS2_COMPAT_TEST_LOCK -eq $Path) {
        $global:CompatibilityTestCalls++
        if ($global:CompatibilityTestCalls -eq 2) { $global:CompatibilityTestLock = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read) }
    }
    $hash
}
'@ | Set-Content -LiteralPath (Join-Path $tools 'Ets2Common.ps1') -Encoding UTF8
    $env:ETS2_COMPAT_TEST_VERSION = '1.62.1.0s'
    $files = @()
    foreach ($name in @('a.scs','b.scs')) {
        $original = [Text.Encoding]::ASCII.GetBytes("prefix|$name|old-suffix")
        $patched = [Text.Encoding]::ASCII.GetBytes("prefix|$name|NEW-suffix")
        [IO.File]::WriteAllBytes((Join-Path $mods $name), $original)
        $patchedFixture = Join-Path $root "$name.patched"
        [IO.File]::WriteAllBytes($patchedFixture, $patched)
        $patchPath = Join-Path $profileRoot "$name.etspatch"
        $writer = New-Object IO.BinaryWriter ([IO.File]::Create($patchPath))
        try {
            $writer.Write([Text.Encoding]::ASCII.GetBytes('ETSPAT01')); $writer.Write([uint32]3)
            $prefix = 7 + $name.Length + 1
            $writer.Write([byte]0); $writer.Write([long]0); $writer.Write([long]$prefix)
            $writer.Write([byte]1); $writer.Write([long]3); $writer.Write([Text.Encoding]::ASCII.GetBytes('NEW'))
            $writer.Write([byte]0); $writer.Write([long]($prefix + 3)); $writer.Write([long]($original.Length - $prefix - 3))
        } finally { $writer.Dispose() }
        $files += [pscustomobject]@{ File = $name; OriginalSha256 = (Get-FileHash (Join-Path $mods $name)).Hash; PatchedSha256 = (Get-FileHash $patchedFixture).Hash; OriginalSize = $original.Length; PatchedSize = $patched.Length; Patch = "$name.etspatch"; PatchSha256 = (Get-FileHash $patchPath).Hash }
    }
    $profile = Join-Path $profileRoot 'profile.json'
    [pscustomobject]@{ Schema = 1; Id = 'test'; GameVersion = '1.62'; Files = $files } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $profile -Encoding UTF8
    $argsMap = @{ Profile = $profile; Source = $mods; BackupRoot = $backupRoot; ResultFile = (Join-Path $root 'result.json') }
    Copy-Item -LiteralPath (Join-Path $root 'a.scs.patched') -Destination (Join-Path $mods 'a.scs') -Force
    $result = & (Join-Path $tools 'Update-ModCompatibility.ps1') @argsMap
    if ($result.Updated.Count -ne 1 -or $result.Installed.Count -ne 2) { throw 'Mixed original/already-patched case failed' }
    if ((Get-FileHash (Join-Path $result.BackupDir 'b.scs')).Hash -ne $files[1].OriginalSha256) { throw 'Original backup mismatch' }
    $ticks = (Get-Item (Join-Path $mods 'b.scs')).LastWriteTimeUtc.Ticks
    $result = & (Join-Path $tools 'Update-ModCompatibility.ps1') @argsMap
    if ($result.Updated.Count -ne 0 -or $result.BackupDir -or (Get-Item (Join-Path $mods 'b.scs')).LastWriteTimeUtc.Ticks -ne $ticks) { throw 'Idempotence failed' }
    foreach ($name in @('a.scs','b.scs')) { [IO.File]::WriteAllBytes((Join-Path $mods $name), [Text.Encoding]::ASCII.GetBytes("prefix|$name|old-suffix")) }
    $global:CompatibilityTestCalls = 0
    $global:CompatibilityTestLock = $null
    $env:ETS2_COMPAT_TEST_LOCK = Join-Path $mods 'b.scs'
    $failed = $false
    try { & (Join-Path $tools 'Update-ModCompatibility.ps1') @argsMap | Out-Null } catch { $failed = $true }
    finally { if ($global:CompatibilityTestLock) { $global:CompatibilityTestLock.Dispose() }; $env:ETS2_COMPAT_TEST_LOCK = $null }
    if (-not $failed -or (Get-FileHash (Join-Path $mods 'a.scs')).Hash -ne $files[0].OriginalSha256 -or (Get-FileHash (Join-Path $mods 'b.scs')).Hash -ne $files[1].OriginalSha256) { throw 'Multi-file rollback after locked destination failed' }
    Copy-Item -LiteralPath (Join-Path $root 'a.scs.patched') -Destination (Join-Path $mods 'a.scs') -Force
    [IO.File]::WriteAllText((Join-Path $mods 'b.scs'), 'unknown content')
    $failed = $false
    try { & (Join-Path $tools 'Update-ModCompatibility.ps1') @argsMap | Out-Null } catch { $failed = $true }
    if (-not $failed -or (Get-FileHash (Join-Path $mods 'a.scs')).Hash -ne $files[0].PatchedSha256) { throw 'Unknown-source protection failed' }
    $env:ETS2_COMPAT_TEST_VERSION = '1.63.0.0s'
    $failed = $false
    try { & (Join-Path $tools 'Update-ModCompatibility.ps1') @argsMap | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Unsupported-game-version protection failed' }
    $env:ETS2_COMPAT_TEST_VERSION = '1.62.1.0s'
    # Wrong expected output hash must fail after generation, before installation.
    [IO.File]::WriteAllBytes((Join-Path $mods 'b.scs'), [Text.Encoding]::ASCII.GetBytes('prefix|b.scs|old-suffix'))
    $files[1].PatchedSha256 = ('0' * 64)
    [pscustomobject]@{ Schema = 1; Id = 'test'; GameVersion = '1.62'; Files = $files } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $profile -Encoding UTF8
    $failed = $false
    try { & (Join-Path $tools 'Update-ModCompatibility.ps1') @argsMap | Out-Null } catch { $failed = $true }
    if (-not $failed -or (Get-FileHash (Join-Path $mods 'b.scs')).Hash -ne $files[1].OriginalSha256) { throw 'Output-hash protection failed' }
    if (@(Get-ChildItem -LiteralPath $root -Directory -Filter '.ets2-uyumluluk-*').Count) { throw 'Temporary files left behind' }
    Write-Output 'PASS: binary copy/literal patch, original backup, mixed state, idempotence, multi-file rollback, unknown source, unsupported game version, output hash failure, temporary cleanup.'
} finally {
    $env:ETS2_COMPAT_TEST_VERSION = $oldTestVersion
    $env:ETS2_COMPAT_TEST_LOCK = $oldTestLock
    $full = [IO.Path]::GetFullPath($root)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($full.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('ets2-compat-test-')) { Remove-Item -LiteralPath $full -Recurse -Force }
}
