Android TV on a Toshiba WT20 next to Windows (dual boot)
=======================================================

This stick installs Android TV next to the Windows already on the tablet. Windows and its
files are not erased. Still, back up anything important before you start: this is an
unofficial build, tested on two tablets only.

Before anything
---------------
- The tablet is on the charger.
- The stick is plugged into the tablet (through an OTG adapter).

Step 1: turn off Secure Boot (once)
-----------------------------------
In Windows: Settings > Update & Security > Recovery > Advanced startup > Restart now
> Troubleshoot > Advanced options > UEFI Firmware Settings > Restart.
In the BIOS screen: Security > Secure Boot > Disabled, then save and exit.

Step 2: prepare Windows
-----------------------
Open the stick in Windows > the "windows" folder > run prepare-windows.cmd and accept the
administrator prompt. The script does this by itself and shows the result in a message:
- shrinks drive C by 40 GB and leaves that space empty for Android;
- turns off hibernation and Fast Startup;
- adds the new boot entry before Windows.
If it says Secure Boot is still on: do step 1 and run the file again.

Step 3: install Android
-----------------------
Restart from the stick: Advanced startup > Use a device > EFI USB Device.
A menu appears, and the install starts by itself after 20 seconds (only on a WT20; it only
uses the free space from step 2). It takes about 10 minutes. Do not turn the tablet off.
When it is done the tablet restarts into Android by itself. Remove the stick.

After the install
-----------------
- Every time the tablet starts, a menu shows for 5 seconds: Android starts by itself; pick
  "Windows" in that menu (volume keys to move, power button to confirm, or a keyboard /
  air mouse) to start Windows.
- From Windows: a normal restart brings you back to Android.

If something goes wrong
-----------------------
- The tablet starts Windows directly and the menu never shows: in Windows run
  windows\boot-fix.cmd.
- To put everything back as before: in Windows run undo-dualboot.cmd (a copy is in
  C:\wt20-dualboot). Then, in Disk Management, delete the Android partitions and extend
  drive C.
- The preparation log: C:\wt20-dualboot\prepare-log.txt
