<#
.SYNOPSIS
    Yerleşik Microsoft RDP denetimini bağıl fare + imleç sıçrama engeliyle barındıran aracı derler.
.DESCRIPTION
    InteropDirectory: MsRdpEx resmi NuGet arşivindeki interop/legacy dizini.
    Üçüncü taraf DLL'ler public repoya konmaz. Çıktı varsayılan local/rdp-stable.
    --self-test bağlantı kurmadan gerçek COM denetimindeki ayarları yazar ve okur.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InteropDirectory,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if(-not $OutputDirectory){$OutputDirectory=Join-Path $repo 'local/rdp-stable'}
$out=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $out -Force | Out-Null
foreach($entry in @(@('Interop.MSTSCLib.dll','Interop.MSTSCLib.dll'),@('net48/AxInterop.MSTSCLib.dll','AxInterop.MSTSCLib.dll'))){
    Copy-Item -LiteralPath (Join-Path $InteropDirectory $entry[0]) -Destination (Join-Path $out $entry[1]) -Force
}
$fw=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$exe=Join-Path $out 'OfisPC-Sabit-Fare.exe'
$source=Join-Path $PSScriptRoot 'rdp/StableRdpClient.cs'
& (Join-Path $fw 'csc.exe') /nologo /target:winexe /platform:x64 /codepage:65001 "/out:$exe" "/reference:$fw\System.Windows.Forms.dll" "/reference:$fw\System.Drawing.dll" "/reference:$out\Interop.MSTSCLib.dll" "/reference:$out\AxInterop.MSTSCLib.dll" $source
if($LASTEXITCODE -ne 0){throw 'RDP istemcisi derlenemedi.'}
$report=Join-Path $out 'self-test.json'
$proc=Start-Process -FilePath $exe -ArgumentList @('--self-test',"`"$report`"") -WindowStyle Hidden -PassThru
if(-not $proc.WaitForExit(15000)){throw 'RDP denetim testi zaman aşımına uğradı.'}
if($proc.ExitCode -ne 0){throw ([IO.File]::ReadAllText($report))}
$result=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
if(-not $result.IgnoreServerGeneratedMouseMoves -or -not $result.RelativeMouseMode -or $result.ConnectionAttempted){throw 'RDP fare ayarları doğrulanamadı.'}
Write-Output "Hazır: $exe"
Write-Output ([IO.File]::ReadAllText($report))
