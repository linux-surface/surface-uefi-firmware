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
$ ./repack.sh ../SurfaceBook2_Win10_19041_22.023.33295.0.msi -o fwupdates
```

Once the script finishes you can find a list of cab files inside of
the fwupdates folder:

```bash
$ tree fwupdates/
fwupdates/
├── SurfaceKeyboard_8.0.2048_96729509-963f-4608-bb2f-4788d0c76404.cab
├── surfaceme_208.8.13570_f3d5747d-24e3-44dd-9118-d332d932bced.cab
├── SurfacePD_1.0.1025_d8a91eed-fb95-4a5f-84db-9497294247e7.cab
├── surfacesam_6.1.12427_52ef6898-ded3-40bc-a1ee-36cc0459b1d4.cab
├── surfacesmf_57.0.299_8230d1a7-94f1-4f2d-934b-5fa2fb6a91c0.cab
├── surfacetouch_4.1.1536_408b2012-cc30-4abc-9fb9-545f18841262.cab
├── SurfaceTPM_7.2.512_a1adec1f-c12a-461d-b69c-114259d40cb6.cab
├── surfacetrackpad_0.8.0_1c12a6dd-54c2-4b20-8c17-3d3372a11096.cab
└── surfaceuefi_15.0.2956_a1bb21b6-5cd1-48ea-ad29-f7c3236ebf0a.cab
```

Using fwupd, you can install all the firmware files at once

``` bash
$ for f in fwupdates/*; do 
    sudo fwupdmgr install --allow-older --allow-reinstall --no-reboot-check "$f"
  done
```
or à la carte

```bash
$ fwupdmgr install --allow-older --allow-reinstall --force <path-to-cab-file>
```


### Why?

Because I don't want to dualboot, and reinstalling Windows every few months
will cost more time over the long run than developing this.

Additionally, this is more open than the Windows firmware update process. This
allows you to downgrade the firmware in the event that you *really really
need to*, unlike Windows.
