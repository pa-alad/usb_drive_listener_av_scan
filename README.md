# USB Drive Listener for Windows Defender Scan

This project listens for Windows volume-arrival events and submits a Microsoft
Defender custom scan for the drive that arrived. It uses Windows Management
Instrumentation (WMI) for event notifications and the Defender PowerShell
cmdlet `Start-MpScan` to request the scan.

The listener responds to **any volume arrival with a drive letter**; it does
not verify that the device is USB or removable media.

## Requirements

- Windows with Windows PowerShell available (`powershell.exe`).
- Microsoft Defender and its `Start-MpScan` cmdlet available and enabled.
- Both scripts saved together in the same directory.
- A user session that can display Windows Forms dialogs.

## Setup

1. Copy [`usb_drive_listener.ps1`](./usb_drive_listener.ps1) and
   [`av_scan.ps1`](./av_scan.ps1) to a stable local directory.
2. Open **Task Scheduler** and create a task to start the listener at the
   desired time, for example, when the user logs on.
3. Configure the task action:
   - **Program/script:** `powershell.exe`
   - **Arguments:** Enter this on one line, replacing the <path> placeholder:

     ```text
     -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "<path>\usb_drive_listener.ps1"
     ```
4. Configure the task to run in the interactive user session (**Run only when
   user is logged on**) so the scan status dialogs can be displayed.
5. Start the task and confirm it remains running. The PowerShell console stays
   hidden; do not end the task if you want drive-arrival monitoring to continue.

The listener starts a separate PowerShell process for each volume-arrival
event. It waits for events rather than polling, and removes handled events from
its queue. If the listener exits, its WMI event subscription is cleaned up.

## What happens when a drive arrives

1. The listener receives a WMI volume-change event.
2. For an arrival event with a drive letter, it starts `av_scan.ps1`.
3. The scan script validates the drive path and asks the user whether to scan.
   The prompt is modal and topmost; dismissing it or closing it does not scan.
4. If the user selects **Scan**, the script starts the Defender command as a
   background job and immediately shows a notice while it runs. The notice does
   not confirm that scanning has started or finished. After it is dismissed,
   the script waits for the command and reports any errors.

**A successful request is not confirmation that a scan is running or complete.**
Keep the drive connected and verify completion in Windows Security.

## Troubleshooting

- If no scan request is made, check that the listener task is running and that
  `av_scan.ps1` is beside the listener script.
- If the scan script reports that Defender is unavailable or cannot submit the
  request, check that Microsoft Defender is enabled and that
  `Start-MpScan` is available in that Windows session.
- The dialogs require an interactive user session. A task running without a
  logged-on user may not be able to display them.
- After changing either script, stop and restart the listener task so it uses
  the updated launcher. The listener console stays hidden. The scan process
  opens a separate PowerShell console while the prompt and scan request run.
- Errors from a scheduled task may not be visible in a console. Check Task
  Scheduler history and the configured task account and permissions.

## Files

- [`usb_drive_listener.ps1`](./usb_drive_listener.ps1) — listens for volume
  arrivals and launches the scan script.
- [`av_scan.ps1`](./av_scan.ps1) — validates the drive and submits a Defender
  custom scan request.
