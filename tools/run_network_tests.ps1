param(
    [string]$Godot = 'G:\.Installed\Godot_v4.5.2-stable_win64.exe\Godot_v4.5.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $projectRoot 'artifacts/base_tests'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot 4.5.2 not found: $Godot" }
$cases = @(
    @{ Name='movement_scene_network_test'; Extra=@() },
    @{ Name='duckov_network_test'; Extra=@() },
    @{ Name='duckov_network_test'; Extra=@('--host-loss') },
    @{ Name='base_five_peer_test'; Extra=@() },
    @{ Name='duckov_animation_network_test'; Extra=@() }
)
foreach ($case in $cases) {
    $suffix = if ($case.Extra.Count) { '_host_loss' } else { '' }
    $log = Join-Path $logRoot ($case.Name + $suffix + '.log')
    $arguments = @('--headless', '--path', $projectRoot, '--script', "res://tests/base/$($case.Name).gd")
    if ($case.Extra.Count) { $arguments += '--'; $arguments += $case.Extra }
    & $Godot @arguments *> $log
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'ERROR:|FAIL:' -Quiet)) {
        throw "Network test failed: $($case.Name). See $log"
    }
    Write-Output "PASS $($case.Name)$suffix -> $log"
}
