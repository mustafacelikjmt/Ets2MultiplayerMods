$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Ets2Common.ps1')
$oldDocs=$env:ETS2KONVOY_DOCS
$root=Join-Path ([IO.Path]::GetTempPath()) ('ets2-profile-test-'+[guid]::NewGuid().ToString('N'))
$env:ETS2KONVOY_DOCS=$root
New-Item -ItemType Directory -Path (Join-Path $root 'profiles/54657374'),(Join-Path $root 'mod') -Force | Out-Null
$script:running=$false
$script:runningSteam=$false
function Get-Process { [CmdletBinding()] param([string[]]$Name) if($script:running -or ($script:runningSteam -and $Name -contains 'steam')){[pscustomobject]@{ProcessName='steam'}} }
try {
 $set=Join-Path $root 'set.json';$backup=Join-Path $root 'backups';$profile=Join-Path $root 'profiles/54657374/profile.sii'
 $mods=@();foreach($name in 'low','high'){
  $path=Join-Path $root "mod/$name.scs";[IO.File]::WriteAllText($path,$name)
  $mods += [pscustomobject]@{File="$name.scs";Source='local';Sha256=(Get-FileSha256 $path)}
 }
 [pscustomobject]@{Mods=$mods;ActiveModLog=@('[mods] Active 2 mods (local: 2, workshop: 0)','[mods] Active local mod low (name: Low, version: 1)','[mods] Active local mod high (name: High, version: 1)')} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $set -Encoding UTF8
 foreach($nl in @("`n","`r`n","`r`r`n")) {
  $original="SiiNunit$nl{$nl user_profile : _nameless.test {$nl profile_name: `"Test`"$nl active_mods: 1$nl active_mods[0]: `"old|Old`"$nl keep_value: `"dokunma`"$nl }$nl}$nl"
  [IO.File]::WriteAllText($profile,$original,(New-Object Text.UTF8Encoding $false))
  $result=Set-Ets2ProfileModOrder -ProfilePath $profile -ModSet $set -BackupRoot $backup
  $changed=[IO.File]::ReadAllText($profile)
  if(-not $changed.Contains('active_mods[0]: "low|Low"') -or -not $changed.Contains('active_mods[1]: "high|High"')){throw 'Reverse order incorrect'}
  $strip='(?m)^[ \t]*active_mods(?:\[\d+\])?[^\r\n]*(?:\r*\n|$)'
  if([regex]::Replace($changed,$strip,'') -cne [regex]::Replace($original,$strip,'')){throw 'Unrelated profile fields changed'}
  $again=Set-Ets2ProfileModOrder -ProfilePath $profile -ModSet $set -BackupRoot $backup
  if($again.Updated){throw 'Idempotence failed'}
  Restore-Ets2ModProfile -BackupDir $result.BackupDir | Out-Null
  if([IO.File]::ReadAllText($profile) -cne $original){throw 'Restore failed'}
 }
 $result=Set-Ets2ProfileModOrder -ProfilePath $profile -ModSet $set -BackupRoot $backup
 [IO.File]::AppendAllText($profile,' ')
 $failed=$false;try{Restore-Ets2ModProfile -BackupDir $result.BackupDir | Out-Null}catch{$failed=$true};if(-not $failed){throw 'Restore overwrote newer profile'}
 $before=Get-FileSha256 $profile;[IO.File]::WriteAllText((Join-Path $root 'mod/low.scs'),'bad')
 $failed=$false;try{Set-Ets2ProfileModOrder -ProfilePath $profile -ModSet $set -BackupRoot $backup | Out-Null}catch{$failed=$true}
 if(-not $failed -or (Get-FileSha256 $profile) -ne $before){throw 'Missing/hash mismatch protection failed'}
 $cloudDir=Join-Path $root 'steam_profiles/436C6F7564';New-Item -ItemType Directory -Path $cloudDir | Out-Null
 $cloudPath=Join-Path $cloudDir 'profile.sii';Copy-Item -LiteralPath $profile -Destination $cloudPath
 $script:runningSteam=$true;$failed=$false
 try{Set-Ets2ProfileModOrder -ProfilePath $cloudPath -ModSet $set -BackupRoot $backup | Out-Null}catch{if($_.Exception.Message -notmatch 'Steam Cloud'){throw};$failed=$true}
 if(-not $failed){throw 'Steam Cloud open-client protection failed'};$script:runningSteam=$false
 # Unsupported binary/invalid array must never be silently rewritten.
 if(-not ('Ets2Mods.ProfileModOrder' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot '../ProfileModOrder.cs')}
 $failed=$false;try{[Ets2Mods.ProfileModOrder]::Decode([Text.Encoding]::ASCII.GetBytes('BSIIinvalid')) | Out-Null}catch{$failed=$true};if(-not $failed){throw 'Unknown encoding accepted'}
 $script:running=$true
 $failed=$false;try{Set-Ets2ProfileModOrder -ProfilePath $profile -ModSet $set -BackupRoot $backup | Out-Null}catch{$failed=$true};if(-not $failed){throw 'Running game protection failed'}
 'PASS profile selection, LF/CRLF/CRCRLF, order reversal, other fields unchanged, backup, idempotence, restore, newer-profile protection, hash mismatch, unsupported format, running game, Steam Cloud guard.'
}finally{
 $env:ETS2KONVOY_DOCS=$oldDocs
 $full=[IO.Path]::GetFullPath($root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if($full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('ets2-profile-test-')){Remove-Item -LiteralPath $full -Recurse -Force}
}
