# Ānanda Āropa - The new initrd & installer combo for LineageOS

## Introduction

Ānanda Āropa (/ɑːˈnʌndə/ /ɑː.ɾɐw.pɐ/) or `aaropa` is BlissLabs' latest attempt in improving the installer & initrd for BlissOS, with some of additional features & improvements compared to the original Android-x86 console installer:

- Refactored Android-x86 init scripts.
- All prebuilts are now being downloaded instead of stored in the repo.
- A new script on initrd to generate fstab that is compatible with [Android's fstab](https://source.android.com/docs/core/architecture/kernel/mounting-partitions-early#fstab-entries).
- A whole new installation environment based on [Devuan ceres](https://www.devuan.org/) with a minimal desktop and an installer that uses [Calamares](https://calamares.io/).

The new installation environment also include programs such as:

- [JWM](https://github.com/joewing/jwm) for the desktop
- [PCManFM-Qt](https://github.com/lxqt/pcmanfm-qt) for file manager
- [QTerminal](https://github.com/lxqt/qterminal) for terminal
- [GParted](https://gparted.org/) for disks & partitions management
- [L3afpad](https://github.com/stevenhoneyman/l3afpad) for text editor
- [GPicView](https://lxde.sourceforge.net/gpicview/) for photo viewer
- [GSmartControl](https://gsmartcontrol.shaduri.dev/) for drive health monitor
- [Htop](https://github.com/htop-dev/htop) for process monitor

With these programs, your installation media is not only for Live booting or install BlissOS, but also to diagnose or debug issues related to the operating system & your PC.

## Compatibility

As of right now, `aaropa` only supports `x86_64`.

## Status

Beside this main repo, `aaropa` is also made of several other repos including:

- [![](https://github.com/BlissOS/aaropa_calamares/actions/workflows/build-devuan-ceres.yml/badge.svg)](https://github.com/BlissOS/aaropa_calamares) <p>
This repo contains patches & modules for Calamares which will be built into .deb file

- ![https://github.com/BlissOS/grub2-themes](https://github.com/BlissOS/grub2-themes/actions/workflows/build-devuan-ceres.yml/badge.svg) <p>
This repo contains the Grub2 theme that we're using which will be built into .deb file

- [![](https://github.com/BlissOS/aaropa_busybox/actions/workflows/build-linux.yml/badge.svg)](https://github.com/BlissOS/aaropa_busybox) <p>
This repo contains `busybox` program that is on initrd, it will also be built into .deb file

- [![](https://github.com/BlissOS/aaropa_devuan_repo/actions/workflows/deplay-pages.yml/badge.svg)](https://github.com/BlissOS/aaropa_devuan_repo) <p>
This repo is a Debian (or Devuan) repository that contains the above programs.

- [![](https://github.com/BlissOS/aaropa_rootfs/actions/workflows/extract-rootfs.yml/badge.svg)](https://github.com/BlissOS/aaropa_rootfs) <p>
This repo is used to generate the `rootfs` image for the installer. It get the above repository to install the programs above and all the program listed in [Introduction](#introduction). After that, it will provide an image contains the installation environemnt, a `grub-rescue.iso` file as the skeleton of BlissOS iso image, and `initrd_lib.tar.gz` contains required programs & libraries for the initrd.

## Usage

If your BlissOS source has `bootable/newinstaller`, remove it. After that, clone this repo to `bootable/aaropa`

```
git clone https://github.com/los-x86/bootable_aaropa.git
```

Once done, run the `download.sh` script on the repo to get all the required files

```
bash bootable/aaropa/download.sh
```

You can also apply [this commit](https://github.com/BlissOS/device_generic_x86_64/commit/866b096a447099b29a9703ae8867aceb3727ef55) to create a `vendorsetup.sh` script which will automatically run whenever you start a build.

After that, just lunch and `make iso_img` like you usually do to build BlissOS.

### Repair menu for installed systems

`build/repair.sh` adds files from `overlay/` to both local and fetched builds:

- `overlay/iso/boot/grub/repair.cfg` and a hook in `iso/boot/grub/grub.cfg`: the USB menu gets **Repair an existing installation**, which lists partitions holding an installed system (`boot/grub/android.cfg` plus `kernel`, `initrd` and `system` image of a slot). Each can be started with the release's default command line or with `boot/grub/android.cfg.good`, without reading a damaged `android.cfg`.
- `overlay/rootfs/usr/bin/bass-repair` (and `bass-live-start`) in `install.sfs`: **Open the repair tool** boots the live session with `BASS_REPAIR=1`, which starts a `dialog` tool instead of the installer. It restores `android.cfg`, rebuilds `grub.cfg`, or reinstalls GRUB to the install's own ESP or disk, asking first and backing files up to `boot/grub/repair-<time>/`. It never writes `data/`, `data.img` or other systems' files without consent.

Fetched releases need `podman` and `squashfs-tools` to add the tool to `install.sfs`; without them only the GRUB entries are added.

### Upgrading an existing installation (local Bass builds)

`build/calamares.sh` rebuilds the installer's Calamares packages from the `[calamares.local]` pins in `aaropa.lock` plus the queues in `vendor/ax86-lite/patches/calamares/<repo>/` (`git am`; `AAROPA_CALAMARES_PATCHES` overrides the directory), in the `build/calamares/Containerfile` Podman image against the pinned upstream Calamares, and installs them in the image:

- `aaropa_calamares_modules_bass`: an **Existing installation** page before partitioning. It finds installed systems (read-only mounts) and offers to upgrade one in place: partitioning and the data image page are skipped, apps and data are kept, and the boot options (`android.cfg` `CMDLINE`) can be kept. Installing an older Android than the one installed is refused. On BIOS it asks before replacing another system's boot code. The page skips itself when there is nothing to ask.
- `aaropa_calamares`: an unformatted target keeps its `data.img` or `data/` unless the user chose to erase it; the bootloader keeps the firmware boot order on upgrade, never overwrites another system's `EFI/Boot/bootx64.efi`, and gives each Bass install its own EFI directory (`BassOS`, `BassOS1`, ...).

`AAROPA_CALAMARES_LOCAL=0` builds the image with the stock packages. Drop the queues once they are merged in Ananda-Aropa and the pins move past them.

## Meaning behind the name

Ānanda & Āropa combines the Sanskrit words "Ananda" (bliss) and "Aropa" (imposing or placing upon), creating a phrase that means "blissful installation" or "blissful startup."

## Credit

- [Android-x86](https://android-x86.org/) for the original initrd & installer in `newinstaller`.
- [Devuan](https://www.devuan.org/) for a linux distro that doesn't use systemd.
- All the programs that are listed above. Without these programs, we couldn't be able to achieve something like this.

And [Shadichy](https://github.com/shadichy), the one who started it all!
