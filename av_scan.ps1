param(
    # Receive the drive letter from the parent script.
    # Example: E:
    [Parameter(Mandatory = $true)]
    [string]$DriveLetter
)

# Convert the drive letter into a root path such as E:\
$ScanPath = $DriveLetter.TrimEnd('\') + '\'

# Make sure the drive still exists before doing anything.
if (-not (Test-Path -Path $ScanPath)) {
    Write-Error "Scan path does not exist: $ScanPath"
    exit 1
}

# Load the WinForms assembly so we can use MessageBox.
# PowerShell's Add-Type cmdlet can load .NET assemblies into the session. [5]
Add-Type -AssemblyName System.Windows.Forms

# Show a popup to inform the user that Windows Defender is about to scan the USB drive.
# MessageBox.Show displays a modal dialog box. [3][4]
[void][System.Windows.Forms.MessageBox]::Show(
    "Windows Defender is starting a scan of the removable drive at:`r`n`r`n$ScanPath`r`n`r`nPlease do not remove the drive until the scan has started.",
    "USB Drive Scan",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
)

# Start a Defender custom scan of that specific path.
# Microsoft documents Start-MpScan with -ScanPath and -ScanType CustomScan. [1]
Start-MpScan -ScanType CustomScan -ScanPath $ScanPath