# In Windows Task Scheduler:
#   Program/script: powershell.exe
#   Arguments: -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\UsbDriveListener.ps1"


# Subscribe to the WMI event class Win32_VolumeChangeEvent.
# This tells PowerShell: "Start listening for volume-related changes"
# such as a USB/removable drive being inserted or removed.
#
# -SourceIdentifier gives this subscription a name ("volumeChange")
# so we can wait specifically for these events later.
#
# Microsoft documents Register-WmiEvent as the cmdlet used to subscribe
# to WMI events, and Win32_VolumeChangeEvent is a standard WMI event
# class for volume changes. [1] [2]
Register-WmiEvent -Class Win32_VolumeChangeEvent -SourceIdentifier volumeChange

# Start an infinite loop so the script keeps running and continues
# listening for drive insert/remove events for as long as the script
# process stays alive.
while ($true) {

    # Pause here until the next event arrives for the subscription
    # named "volumeChange".
    #
    # Wait-Event blocks execution until a matching event is raised,
    # instead of constantly polling in a tight loop. [4]
    $event = Wait-Event -SourceIdentifier volumeChange

    # Pull the EventType value out of the event object.
    #
    # For Win32_VolumeChangeEvent, Microsoft documents:
    #   1 = Configuration changed
    #   2 = Device arrival
    #   3 = Device removal
    #   4 = Docking
    #
    # So EventType 2 means a drive/device has just arrived. [2]
    $type = $event.SourceEventArgs.NewEvent.EventType

    # Only continue if the event was "device arrival".
    # That means we ignore removals and other volume-related changes.
    if ($type -eq 2) {

        # Get the drive letter from the event, if one exists.
        # Example values might be "E:" or "F:".
        #
        # Not every event is guaranteed to provide a drive letter,
        # so we check it before using it.
        $driveLetter = $event.SourceEventArgs.NewEvent.DriveName

        # Only run our follow-up action if PowerShell actually received
        # a drive letter.
        if ($driveLetter) {

            # Launch a *new* PowerShell process and tell it to run
            # another script file.
            #
            # This is where you plug in the script that should run when
            # a removable drive is inserted.
            #
            # -NoProfile avoids loading the user's PowerShell profile,
            # which makes execution more predictable.
            #
            # Start-Process is used here so the "listener" script keeps
            # running in the background while the real action script
            # runs separately.
            Start-Process powershell.exe -ArgumentList '-NoProfile -File "C:\Scripts\DoSomething.ps1"'
        }
    }

    # Remove the event we just handled from the current PowerShell
    # session's event queue.
    #
    # This is important because Wait-Event / Get-Event work with an
    # event queue in the session. If you never remove handled events,
    # they can build up over time. [6] [7]
    Remove-Event -EventIdentifier $event.EventIdentifier
}