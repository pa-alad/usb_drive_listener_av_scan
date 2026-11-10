# Accept the drive letter from the listener to scan the newly inserted volume.
param(
    # Receive the drive letter from the parent script.
    # Example: E:
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DriveLetter
)

# Report errors to the console and, when possible, in a dialog box.
function Show-ScanError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Error $Message

    try {
        [void][System.Windows.Forms.MessageBox]::Show(
            $Message,
            'USB Drive Scan',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    } catch {
        # Ignore UI errors; the console error message is enough for unattended execution.
    }
}

# Validate the drive and target path before asking Defender to scan.
try {
    if ($DriveLetter -notmatch '^[A-Za-z]:$') {
        throw "Drive letter '$DriveLetter' is not valid. Expected a format like E:."
    }

    $ScanPath = $DriveLetter.TrimEnd('\') + '\'

    if (-not (Test-Path -Path $ScanPath -PathType Container)) {
        throw "Scan path does not exist: $ScanPath"
    }

    if (-not (Get-Command -Name Start-MpScan -ErrorAction SilentlyContinue)) {
        throw 'Windows Defender is not available on this system.'
    }

    # Load the WinForms assembly only when we need the user-facing dialog box.
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

    # Submit the scan request; this cmdlet does not confirm that scanning has completed.
    Start-MpScan -ScanType CustomScan -ScanPath $ScanPath -ErrorAction Stop

    # Report only that the request was submitted, not that scanning has started or finished.
    try {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Windows Defender accepted a scan request for:`r`n`r`n$ScanPath`r`n`r`n" +
            'This does not confirm scan status. Keep the drive connected and verify completion ' +
            'in Windows Security.',
            'USB Drive Scan',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } catch {
        Write-Warning (
            'Scan request was submitted, but the confirmation dialog could not be displayed: ' +
            $_.Exception.Message
        )
    }
    Write-Host "Defender scan request submitted for $ScanPath"
    exit 0
} catch {
    # Report validation errors and failures to submit the scan request without claiming scan state.
    Show-ScanError -Message (
        "Failed to submit Windows Defender scan request for ${DriveLetter}: " +
        $_.Exception.Message
    )
    exit 1
}