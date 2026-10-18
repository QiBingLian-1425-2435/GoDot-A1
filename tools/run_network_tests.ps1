param(
    [string]$Godot = 'G:\.Installed\Godot_v4.5.2-stable_win64.exe\Godot_v4.5.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot not found: $Godot. Pass -Godot with your 4.5.2 executable." }

function Run-NetworkSuite([string]$TestName, [int]$ClientCount) {
    $processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
    try {
        for ($slot = 0; $slot -le $ClientCount; $slot++) {
            $role = if ($slot -eq 0) { 'host' } else { 'client' }
            $stdout = Join-Path $logRoot "$TestName-$slot.stdout.log"
            $stderr = Join-Path $logRoot "$TestName-$slot.stderr.log"
            $arguments = @('--headless', '--path', ('"{0}"' -f $projectRoot), '--script', "res://tests/$TestName.gd", '--', $role)
            $process = Start-Process -FilePath $Godot -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            $processes.Add($process)
            if ($slot -eq 0) {
                $readyUntil = [DateTime]::UtcNow.AddSeconds(12)
                do {
                    Start-Sleep -Milliseconds 100
                    $ready = (Test-Path -LiteralPath $stdout) -and (Select-String -LiteralPath $stdout -Pattern 'NETWORK_READY' -Quiet)
                    if ($process.HasExited) { throw "$TestName host exited before ready. See $stdout and $stderr" }
                } until ($ready -or [DateTime]::UtcNow -gt $readyUntil)
                if (-not $ready) { throw "$TestName host readiness timeout" }
            }
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        while (@($processes | Where-Object { -not $_.HasExited }).Count -gt 0) {
            if ([DateTime]::UtcNow -gt $deadline) { throw "$TestName process timeout" }
            Start-Sleep -Milliseconds 100
        }
        for ($slot = 0; $slot -lt $processes.Count; $slot++) {
            $processes[$slot].WaitForExit()
            $stderr = Join-Path $logRoot "$TestName-$slot.stderr.log"
            $stdout = Join-Path $logRoot "$TestName-$slot.stdout.log"
            if ($processes[$slot].ExitCode -ne 0 -or (Get-Item -LiteralPath $stderr).Length -ne 0) {
                throw "$TestName process $slot failed (exit $($processes[$slot].ExitCode)); see $stdout and $stderr"
            }
            $marker = if ($TestName -eq 'network_five_test') { 'FIVE PROCESS .* COMPLETE: 0 failures' } else { 'NETWORK .* COMPLETE' }
            if (-not (Select-String -LiteralPath $stdout -Pattern $marker -Quiet)) { throw "$TestName process $slot did not finish its assertions" }
        }
        Write-Output "$TestName PASS: $($processes.Count) processes exited 0, completion markers present, stderr empty"
    }
    finally {
        foreach ($process in $processes) {
            if (-not $process.HasExited) { $process.Kill($true) }
            $process.Dispose()
        }
    }
}

Run-NetworkSuite 'network_test' 1
Run-NetworkSuite 'network_five_test' 4
