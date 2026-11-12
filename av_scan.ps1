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

# Ask for consent in a topmost modal form so the choice is visible above other windows.
function Confirm-DriveScan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'USB Drive Scan'
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $true
    $form.TopMost = $true

    $message = New-Object System.Windows.Forms.Label
    $message.Text = (
        "A drive was inserted at $Path.`r`n" +
        "Would you like to scan it with Windows Defender?`r`n`r`n" +
        'Ensure Defender security intelligence definitions are up to date.'
    )
    $message.AutoSize = $true
    $message.MaximumSize = New-Object System.Drawing.Size(395, 0)
    $message.Location = New-Object System.Drawing.Point(16, 16)
    $form.Controls.Add($message)

    # Size the dialog and place the buttons after the wrapped message.
    $buttonY = $message.Bottom + 18
    $form.ClientSize = New-Object System.Drawing.Size(440, ($buttonY + 46))

    $scanButton = New-Object System.Windows.Forms.Button
    $scanButton.Text = 'Scan'
    $scanButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $scanButton.Location = New-Object System.Drawing.Point(220, $buttonY)
    $scanButton.Size = New-Object System.Drawing.Size(90, 30)
    $form.Controls.Add($scanButton)

    $dismissButton = New-Object System.Windows.Forms.Button
    $dismissButton.Text = 'Dismiss'
    $dismissButton.DialogResult = [System.Windows.Forms.DialogResult]::No
    $dismissButton.Location = New-Object System.Drawing.Point(320, $buttonY)
    $dismissButton.Size = New-Object System.Drawing.Size(90, 30)
    $form.Controls.Add($dismissButton)

    $form.CancelButton = $dismissButton
    $form.Add_Shown({
        $form.Activate()
        $form.BringToFront()
    })

    try {
        return $form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::Yes
    } finally {
        $form.Dispose()
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

    # Do not submit a scan request unless the user explicitly chooses Scan.
    if (-not (Confirm-DriveScan -Path $ScanPath)) {
        Write-Host "Scan dismissed for $ScanPath"
        exit 0
    }

    # Run Defender in a job so the notification need not wait for the command to finish.
    $scanJob = Start-MpScan -ScanType CustomScan -ScanPath $ScanPath `
        -AsJob -ErrorAction Stop

    try {
        # This reports that the command was queued, not that scanning has completed.
        [void][System.Windows.Forms.MessageBox]::Show(
            "Windows Defender is processing a scan request for:`r`n`r`n$ScanPath`r`n`r`n" +
            'This does not confirm that scanning has started or finished. Keep the drive ' +
            'connected and verify completion in Windows Security.',
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

    # Keep this session alive until the job finishes, then check its result.
    try {
        Wait-Job -Job $scanJob -ErrorAction Stop | Out-Null
        if ($scanJob.State -ne 'Completed') {
            $jobReason = $scanJob.ChildJobs[0].JobStateInfo.Reason
            if ($null -ne $jobReason) {
                throw $jobReason
            }
            throw "Defender scan command ended with state '$($scanJob.State)'."
        }
        Receive-Job -Job $scanJob -ErrorAction Stop | Out-Null
    } finally {
        Remove-Job -Job $scanJob -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Defender scan command completed for $ScanPath"
    exit 0
} catch {
    # Report validation errors and failures to submit or run the scan command.
    Show-ScanError -Message (
        "Failed to submit Windows Defender scan request for ${DriveLetter}: " +
        $_.Exception.Message
    )
    exit 1
}