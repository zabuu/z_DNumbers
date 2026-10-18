param([switch]$Deploy)

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

$command = 'call "' + $vcvars + '" x86 >nul && cl /nologo /LD /O2 /MT /EHsc ' +
  '/std:c++17 /DWIN32_LEAN_AND_MEAN /D_X86_ ' +
  '/I"' + (Join-Path $minhook "include") + '" ' +
  '/I"' + (Join-Path $minhook "src") + '" ' +
  '/I"' + (Join-Path $minhook "src\hde") + '" ' +
  $inputs + ' /link /DEF:"' + $definition + '" /OUT:"' +
  (Join-Path $output "zAPI.dll") + '" user32.lib kernel32.lib'

Push-Location -LiteralPath $output
try {
    cmd.exe /d /s /c $command
    if ($LASTEXITCODE -ne 0) { throw "zAPI build failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

$rootDll = "g:\Games\OctoWoW\zAPI.dll"
if ($Deploy -and (Test-Path "g:\Games\OctoWoW")) {
    try {
        Copy-Item (Join-Path $output "zAPI.dll") $rootDll -Force -ErrorAction Stop
        Write-Host "Deployed zAPI.dll to $rootDll"
    } catch {
        throw "DLL deployment failed. Close the game fully before deploying: $($_.Exception.Message)"
    }
}
