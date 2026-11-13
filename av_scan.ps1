param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DriveLetter
)

function Get-DriveScanPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Letter
    )

    if ($Letter -notmatch '^[A-Za-z]:$') {
        throw "Drive letter '$Letter' is invalid. Expected a format like E:."
    }

    $scanPath = $Letter.TrimEnd('\') + '\'
    if (-not (Test-Path -Path $scanPath -PathType Container)) {
        throw "Scan path does not exist: $scanPath"
    }

    return $scanPath
}

function Confirm-DriveScanUsingPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScanPath
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
        "A drive was inserted at $ScanPath.`r`n" +
        "Would you like to scan it with Windows Defender?`r`n`r`n" +
        'Ensure Defender security intelligence definitions are up to date.'
    )
    $message.AutoSize = $true
    $message.MaximumSize = New-Object System.Drawing.Size(395, 0)
    $message.Location = New-Object System.Drawing.Point(16, 16)
    $form.Controls.Add($message)

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

function Show-ScanRequestNotice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScanPath
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        "Windows Defender is processing a scan request for:`r`n`r`n$ScanPath`r`n`r`n" +
        'This does not confirm that scanning has started or finished. Keep the drive ' +
        'connected and verify completion in Windows Security.',
        'USB Drive Scan',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

function Wait-ForDefenderScanJob {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Job]$Job
    )

    try {
        Wait-Job -Job $Job -ErrorAction Stop | Out-Null
        if ($Job.State -ne 'Completed') {
            $jobReason = $Job.ChildJobs[0].JobStateInfo.Reason
            if ($null -ne $jobReason) {
                throw $jobReason
            }

            throw "Defender scan command ended with state '$($Job.State)'."
        }

        Receive-Job -Job $Job -ErrorAction Stop | Out-Null
    } finally {
        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-DriveScan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Letter
    )

    $scanPath = Get-DriveScanPath -Letter $Letter
    if (-not (Get-Command -Name Start-MpScan -ErrorAction SilentlyContinue)) {
        throw 'Windows Defender is not available on this system.'
    }

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    if (-not (Confirm-DriveScanUsingPrompt -ScanPath $scanPath)) {
        Write-Host "Scan dismissed for $scanPath"
        return
    }

    $scanJob = Start-MpScan -ScanType CustomScan -ScanPath $scanPath `
        -AsJob -ErrorAction Stop

    try {
        Show-ScanRequestNotice -ScanPath $scanPath
    } catch {
        Write-Warning (
            'Scan request was submitted, but the confirmation dialog could not be displayed: ' +
            $_.Exception.Message
        )
    }

    Wait-ForDefenderScanJob -Job $scanJob
    Write-Host "Defender scan command completed for $scanPath"
}

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
        Write-Warning "Could not display the error dialog: $($_.Exception.Message)"
    }
}


try {
    Invoke-DriveScan -Letter $DriveLetter
} catch {
    Show-ScanError -Message (
        "Failed to process Defender scan for ${DriveLetter}: " +
        $_.Exception.Message
    )
    exit 1
}
