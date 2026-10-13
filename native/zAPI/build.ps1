$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $project "src\zAPI.cpp"
$definition = Join-Path $project "src\zAPI.def"
$minhook = Join-Path $project "vendor\minhook"
$output = Join-Path $project "build"
$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"

New-Item -ItemType Directory -Path $output -Force | Out-Null

$inputs = @(
  ('"' + $source + '"'),
  ('"' + (Join-Path $minhook "src\buffer.c") + '"'),
  ('"' + (Join-Path $minhook "src\hook.c") + '"'),
  ('"' + (Join-Path $minhook "src\trampoline.c") + '"'),
  ('"' + (Join-Path $minhook "src\hde\hde32.c") + '"')
) -join " "

$command = 'call "' + $vcvars + '" x86 >nul && cl /nologo /LD /O1 /MT /EHsc ' +
  '/std:c++17 /DWIN32_LEAN_AND_MEAN /D_X86_ ' +
  '/I"' + (Join-Path $minhook "include") + '" ' +
  '/I"' + (Join-Path $minhook "src") + '" ' +
  '/I"' + (Join-Path $minhook "src\hde") + '" ' +
  $inputs + ' /link /DEF:"' + $definition + '" /OUT:"' +
  (Join-Path $output "zAPI.dll") + '" user32.lib kernel32.lib'

cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw "zAPI build failed with exit code $LASTEXITCODE" }

$rootDll = "g:\Games\OctoWoW\zAPI.dll"
if (Test-Path "g:\Games\OctoWoW") {
    try {
        Copy-Item (Join-Path $output "zAPI.dll") $rootDll -Force -ErrorAction Stop
        Write-Host "Deployed zAPI.dll to $rootDll"
    } catch {
        $tempOld = "g:\Games\OctoWoW\zAPI_" + (Get-Random) + ".old"
        Move-Item $rootDll $tempOld -Force
        Copy-Item (Join-Path $output "zAPI.dll") $rootDll -Force
        Write-Host "Deployed zAPI.dll to $rootDll (previous version moved to $tempOld)"
    }
}
