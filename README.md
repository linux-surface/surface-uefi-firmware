# UEFI firmware updates for linux-surface

This is a (mostly) automated patcher for converting the UEFI firmware updates
that Microsoft ships with their official driver installation packages into a
format that can be installed under linux using `fwupd`.

Luckily for us Microsoft uses UEFI capsules for their firmwares, which is a
standarized format already supported by `fwupd`. All we have to do is add a
little bit of metadata, which can be automated.

### Download?

Not yet, there is still some stuff that needs to be ironed out. However, in
the meantime, you can create the neccessary files yourself.

### How?

```C
#include <std_disclaimer.h>

/*
 * You are attempting to flash the firmware on an extemely locked down system.
 * It is unknown if the device can recover itself from a bad firmware flash.
 * 
 * NO responsibility is taken for damages to your hardware or any other
 * consequences you may face because of flashing your firmware using unofficial
 * and unsupported tools.
 *
 * Be careful!
 */
```

First you need to download the driver package for your surface model from
Microsofts website. It will present you with a list of files, they are for
multiple versions of Windows. Just use the first one.

https://support.microsoft.com/en-us/help/4023482/surface-download-drivers-and-firmware-for-surface

You will also have to install the `msiextract`, `gcab` and `dos2unix` programs through
your distributions package manager.

```bash
# Debian based
$ sudo apt install msitools gcab dos2unix

# Arch based, msitools is in the AUR, use whatever helper you like
$ yay -S gcab msitools dos2unix

# Fedora
$ sudo dnf install msitools gcab dos2unix
```

We are going to assume you have a directory tree that looks like this, and
that you are currently in the `surface-uefi-firmware` directory:

```
.
├── SurfaceBook2_Win10_18362_20.012.20538.0.msi
└── surface-uefi-firmware
    ├── prep.sh
    ├── README.sh
    ├── repack.sh
    └── template.metainfo.xml

1 directory, 5 files
```

First you need to run the MSI you just downloaded through the `prep.sh` script.

This script will make sure that the first part of the filename clearly
identifies the model and SKU (WiFi vs LTE). It will output the new filename
of the file (or the old one if no changes were neccessary), please use that
as of now.

```bash
$ ./prep.sh ../SurfaceBook2_Win10_18362_20.012.20538.0.msi
 > No changes neccessary! Filename stays SurfaceBook2_Win10_18362_20.012.20538.0.msi
```

Now run the `repack.sh` script which will unpack the MSI, extract all UEFI
firmwares from it, and generate `fwupd` metadata for it.

We are going to invoke it in `cab` mode, which will additionally package the
firmwares so that you can flash them directly using `fwupd`.

```bash
$ ./repack.sh -m cab -f ../SurfaceBook2_Win10_18362_20.012.20538.0.msi -o out
```

Once the script finishes you can find a list of cab files inside of the out
folder:

```bash
$ ls -l out/**/*.cab
out/SurfaceBook2/SurfaceBook2_SurfaceISH_36.567.12.0.cab
out/SurfaceBook2/SurfaceBook2_SurfaceTouch_0_238.0.1.1.cab
out/SurfaceBook2/SurfaceBook2_SurfaceME_11.8.50.3448.cab
out/SurfaceBook2/SurfaceBook2_SurfaceTouch_238.0.1.1.cab
out/SurfaceBook2/SurfaceBook2_SurfaceSAM_182.1004.139.0.cab
out/SurfaceBook2/SurfaceBook2_SurfaceUEFI_389.2837.768.0.cab
```

You can now install them with `fwupd`

```bash
$ fwupdmgr install <path to cab file>
```

### Why?

Because I don't want to dualboot, and reinstalling Windows every few months
will cost more time over the long run than developing this.

Additionally, this is more open than the Windows firmware update process. This
allows you to downgrade the firmware in the event that you *really really 
need to*, unlike Windows.

### But I don't want to do all of this myself!

So, it is possible to set up a custom remote for fwupd, so that you can get
updates like through your package manager. Sadly, the whole process is very
much geared towards the official remote (the LVFS), so it needs some work to
iron out all the details and to integrate them into our current repository
management system.

The main issue is that it's almost impossible to automate the generation
of the metadata any further, because Microsofts website does not support
scripted downloads.

This means a real person needs to monitor it for changes, download the updated
MSIs, generate the metadata by hand, and then upload it to the CI which could
then process it further and generate repository metadata. But as mentioned
before, this will need some work, especially since we don't want to rush out
something that might impact not just your installation but the actual hardware.
