# In Windows Task Scheduler:
#   Program/script: powershell.exe
#   Arguments: -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File
#              "<absolute path>\UsbDriveListener.ps1"

# Keep the event name and scan-script path together for easy configuration.
$EventSourceIdentifier = 'volumeChange'
$ScanScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'av_scan.ps1'

# Register the WMI volume-change event once and keep the listener alive indefinitely.
try {
    Register-WmiEvent -Class Win32_VolumeChangeEvent `
        -SourceIdentifier $EventSourceIdentifier -ErrorAction Stop | Out-Null

    # Wait for each event and keep listening while this process is running.
    while ($true) {
        try {
            $event = Wait-Event -SourceIdentifier $EventSourceIdentifier -ErrorAction Stop
        } catch {
            if ($_.FullyQualifiedErrorId -eq 'NoEventsFound') {
                continue
            }
            throw
        }

        # EventType 2 means volume arrival; ignore removals and other changes.
        $driveLetter = $null
        try {
            $type = $event.SourceEventArgs.NewEvent.EventType
            if ($type -eq 2) {
                $driveLetter = $event.SourceEventArgs.NewEvent.DriveName
                if ($driveLetter) {
                    # Quote the path because Start-Process joins arguments into one command line.
                    $resolvedAvScanScriptPath = [System.IO.Path]::GetFullPath($ScanScriptPath)
                    if (-not (Test-Path -Path $resolvedAvScanScriptPath -PathType Leaf)) {
                        throw "Scan script not found: $resolvedAvScanScriptPath"
                    }

                    $scanArguments = @(
                        '-NoProfile'
                        '-STA'
                        '-ExecutionPolicy'
                        'Bypass'
                        '-File'
                        ('"{0}"' -f $resolvedAvScanScriptPath)
                        '-DriveLetter'
                        $driveLetter
                    )

                    Start-Process -FilePath 'powershell.exe' `
                        -ArgumentList $scanArguments
                }
            }
        } catch {
            Write-Warning (
                "Failed to process volume event for drive '$driveLetter': " +
                $_.Exception.Message
            )
        } finally {
            # Remove handled events to prevent the event queue from growing.
            if ($null -ne $event) {
                Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
            }
        }
    }
} catch {
    # Report startup or listener failures instead of continuing without event handling.
    Write-Error "Failed to register or process drive change events: $($_.Exception.Message)"
    exit 1
} finally {
    # Clean up the subscription whenever the listener exits.
    Unregister-Event -SourceIdentifier $EventSourceIdentifier -ErrorAction SilentlyContinue
    Remove-Event -SourceIdentifier $EventSourceIdentifier -ErrorAction SilentlyContinue
}