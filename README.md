# UEFI firmware updates for linux-surface

This is a (mostly) automated patcher for converting the UEFI firmware updates
that Microsoft ships with their official driver installation packages into a
format that can be installed under linux using fwupd.

Luckily for us Microsoft uses UEFI capsules for their firmwares, which is a
standarized format already supported by fwupd. All we have to do is add a
little bit of metadata.

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
├── SurfaceBook2_Win10_19041_22.023.33295.0.msi
└── surface-uefi-firmware
    ├── README.sh
    ├── repack.sh
    └── template.metainfo.xml

1 directory, 4 files
```

You will need to run the `repack.sh` script, which will unpack the MSI,
extract all UEFI firmwares from it, and generate fwupd metadata for it.

```bash
$ ./repack.sh -f ../SurfaceBook2_Win10_19041_22.023.33295.0.msi -o out
```

Once the script finishes you can find a list of cab files inside of the out
folder:

```bash
$ ls -l out
out/SurfaceISH_36.2.14092_7a8be0e8-239e-452c-8281-ca184427982c.cab
out/SurfaceTouch_0_242.11.271_5773662e-2343-48b5-b018-db09eae2ea41.cab
out/SurfaceTouch_242.0.261_5917bcbe-626f-4b76-89d1-b0a8b7a6707a.cab
out/surfaceme_184.90.3987_5f0f3ae0-5d9d-4d64-9385-1fa696ab1719.cab
out/surfacesam_182.9.139_37da9c3d-6b50-4dbf-82b8-46ca912d98f2.cab
out/surfaceuefi_98.1.8960_6726b589-d1de-4f26-b2d7-7ac953210d39.cab
```

You can now install them with fwupd

```bash
$ fwupdmgr install --allow-older --allow-reinstall --force <path to cab file>
```

### Why?

Because I don't want to dualboot, and reinstalling Windows every few months
will cost more time over the long run than developing this.

Additionally, this is more open than the Windows firmware update process. This
allows you to downgrade the firmware in the event that you *really really
need to*, unlike Windows.
