# Listens for USB drive insertions and runs av_scan.ps1 on that event.
#
# To be run by Windows Task Scheduler at user login:
#   Program/script: powershell.exe
#   Arguments: -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass
#              -File "<absolute path>\usb_drive_listener.ps1"

function Start-AvScanProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter
    )

    try {
        $avScanScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'av_scan.ps1'
        $resolvedAvScanScriptPath = [System.IO.Path]::GetFullPath($avScanScriptPath)
        if (-not (Test-Path -Path $resolvedAvScanScriptPath -PathType Leaf)) {
            throw "AV scan script not found: $resolvedAvScanScriptPath"
        }

        $processArguments = @(
            '-NoProfile'
            '-STA'
            '-ExecutionPolicy'
            'Bypass'
            '-File'
            ('"{0}"' -f $resolvedAvScanScriptPath)
            '-DriveLetter'
            $DriveLetter
        )

        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList $processArguments -ErrorAction Stop
    } catch {
        Write-Warning (
            "Failed to launch the scan script for drive '$DriveLetter': " +
            $_.Exception.Message
        )
    }
}

function Get-InsertedDriveName {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSEventArgs]$VolumeEvent
    )

    $volumeChange = $VolumeEvent.SourceEventArgs.NewEvent
    # NB. EventType 2 for drive arrivals
    if ($volumeChange.EventType -ne 2 -or -not $volumeChange.DriveName) {
        return
    }

    return $volumeChange.DriveName
}


$EventSourceIdentifier = 'volumeChange'

try {
    Register-WmiEvent -Class Win32_VolumeChangeEvent `
        -SourceIdentifier $EventSourceIdentifier -ErrorAction Stop | Out-Null

    while ($true) {
        # NB. Blocks waiting for an event
        $volumeEvent = Wait-Event -SourceIdentifier $EventSourceIdentifier -ErrorAction Stop

        try {
            $driveLetter = Get-InsertedDriveName -VolumeEvent $volumeEvent
            if ($driveLetter) {
                Start-AvScanProcess -DriveLetter $driveLetter
            }
        } finally {
            Remove-Event -EventIdentifier $volumeEvent.EventIdentifier `
                -ErrorAction SilentlyContinue
        }
    }
} catch {
    Write-Error "Drive listener stopped unexpectedly: $($_.Exception.Message)"
    exit 1
} finally {
    Unregister-Event -SourceIdentifier $EventSourceIdentifier -ErrorAction SilentlyContinue
    Remove-Event -SourceIdentifier $EventSourceIdentifier -ErrorAction SilentlyContinue
}
