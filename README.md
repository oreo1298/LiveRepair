# LiveRepair

A lightweight live ISO for repairing, recovering, cloning and checking computers, with these
programs preinstalled and ready to use:

| Program | Repository | What it does |
|---|---|---|
| **CloneAndRecover** | [CloneAndRecover](https://github.com/oreo1298/CloneAndRecover) | Clone disks (also to smaller ones), image and restore them, rescue failing disks with GNU ddrescue |
| **RecoverAll** | [RecoverAll](https://github.com/oreo1298/RecoverAll) | Recover deleted files, lost partitions and photos; repair and image disks |
| **DiskHealth** | [DiskHealth](https://github.com/oreo1298/DiskHealth) | S.M.A.R.T., health, benchmarks and surface tests for HDDs, SSDs, NVMe and flash drives |
| **ManageDisks** | [ManageDisks](https://github.com/oreo1298/ManageDisks) | Disk and partition manager (GUI and a diskpart-style CLI), including Mac HFS+ and APFS |
| **TM5 for Linux** | [TM5Linux](https://github.com/oreo1298/TM5Linux) | RAM stability test with TestMem5 configs (Extreme1 by anta777 and others) |
| **FastCopy Linux** | [FastCopyLinux](https://github.com/oreo1298/FastCopyLinux) | Fast file copy, sync, move and delete with verification |
| **LinBurn** | [ImgBurnLinux](https://github.com/oreo1298/ImgBurnLinux) | ImgBurn-style CD/DVD/Blu-ray burning, reading, building and verifying |
| **Rufux** | [WindowsUSBLinux](https://github.com/oreo1298/WindowsUSBLinux) | Rufus-style bootable USB drives from Windows and Linux images |
| **VirtConvert&Create** | [VirtConvert](https://github.com/oreo1298/VirtConvert) | Convert and create virtual disks (VDI, VMDK, VHD, VHDX, QCOW2, OVA) |

Every prerequisite is included: Qt 6 with PySide6 and PyQt6, GTK 4 with libadwaita and PyGObject,
ddrescue, partclone, sleuthkit, smartmontools, fio, nvme-cli, qemu-img, wimlib, xorriso, cdrdao,
cdrtools, dvd+rw-tools, GRUB, the Rufus UEFI:NTFS image, mdadm, cryptsetup, xxHash, and the tools
for FAT, exFAT, NTFS, ext4, Btrfs, XFS, F2FS, JFS, UDF, HFS+ and APFS. **Firefox** is included too.

The HFS+ and APFS tools that ManageDisks uses are not in Arch's repositories, so this repository
builds them itself from [`packages/`](packages): `hfsprogs` (from the AUR recipe, plus the `fsck.hfs`
name for classic HFS) and `apfsprogs` (pinned to its v0.2.1 release).

## Build the ISO

The ISO is built from the latest version of each program (the default branch of each repository)
whenever you build it. It needs about 10 GB of free disk space and an internet connection.

On Arch Linux or an Arch-based distribution (CachyOS, EndeavourOS, Manjaro...):

```sh
git clone https://github.com/oreo1298/LiveRepair.git
cd LiveRepair
sudo ./build.sh
```

This installs the build tools that are missing (archiso, GRUB, sbsigntools, base-devel and what
each program needs to build) and a `builder` user, because makepkg does not run as root. It does not update
your system, and it compiles for any x86-64 PC whatever your own compiler settings are (some
Arch-based systems, such as CachyOS, may be set up to compile for newer CPUs only).

On any Linux with Docker or Podman, Arch-based or not (the build runs in an Arch Linux
container, so nothing is installed on your computer):

```sh
git clone https://github.com/oreo1298/LiveRepair.git
cd LiveRepair
sudo scripts/build-in-docker.sh
```

Docker's service has to be running: if the script says it is not, start it with
`sudo systemctl start docker` (or `sudo systemctl enable --now docker` to start it at every boot).
The script uses Podman instead when Docker is not installed or not running.

The ISO lands in `out/` (`liverepair-YYYY.MM.DD-x86_64.iso`, about 1.5 GB), with its SHA-256
checksum and a list of the programs and packages in it. The build stops with an error if the ISO
would not fit on a single-layer DVD (4.7 GB). The first build also makes your own Secure Boot key,
in `keys/` (see [Secure Boot](#secure-boot)): keep that folder for your next builds.

To build a program from your own checkout instead of GitHub, set `APP_SRC_<Repository>`, for
example `sudo APP_SRC_DiskHealth=~/src/DiskHealth ./build.sh`.

## Put it on a DVD or USB drive

- **DVD**: burn the ISO as a disc image with LinBurn, ImgBurn, Brasero or K3b, or from a terminal:
  `growisofs -dvd-compat -Z /dev/sr0=liverepair-*.iso` (or `xorriso -as cdrecord -v dev=/dev/sr0
  -eject liverepair-*.iso`). The disc boots with UEFI (GRUB) and with legacy BIOS (syslinux).
- **USB drive**: write it with Rufux, Rufus (DD mode), balenaEtcher or Ventoy, or with
  `sudo dd if=liverepair-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`.

Then boot from it, with Secure Boot on or off.

## Secure Boot

The ISO boots with Secure Boot on. Only Microsoft can sign boot loaders that every PC trusts, so
the ISO starts with **shim**, the small boot loader that Ubuntu, Fedora and other distributions
use, signed by Microsoft (this is Ubuntu's). shim starts the rest (GRUB, the Linux kernel,
Memtest86+) only if it is signed with a key the PC's owner has approved. The ISO's are signed with
your own key, which the first build makes in `keys/`, so each PC needs to approve it once:

1. Boot the ISO. A blue screen says **Verification failed: (0x1A) Security Violation**: press
   Enter.
2. **Shim UEFI key management** appears: press a key within 10 seconds (if you miss it, start
   the PC from the ISO again).
3. Choose **Enroll key from disk**, then the disc's `ARCHISO_EFI` volume, then
   `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`.
4. **View key 0** shows the key: *LiveRepair Secure Boot (date)*, and its fingerprint, which
   should match the "SHA-1 fingerprint" that your build printed. Then choose **Continue**,
   **Yes** and **Reboot**.

From then on, that PC boots every LiveRepair ISO signed with the same key, without asking.

Good to know:

- **Keep `keys/`, and keep it private.** Builds that use the same key need no new approval; an ISO
  built with another key (on another computer, or after deleting `keys/`) has to be approved
  again. Anyone who has `liverepair-secureboot.key` can make boot media that PCs with your key
  enrolled will start, so do not share or publish it (it is in `.gitignore`).
- To sign with a key you already have, for example one your PCs already trust:
  `sudo SECUREBOOT_KEY=/path/my.key SECUREBOOT_CERT=/path/my.crt ./build.sh` (also with
  `scripts/build-in-docker.sh`). `sudo SECUREBOOT=0 ./build.sh` builds an ISO without Secure
  Boot support, which then boots only with Secure Boot off.
- To remove the key from a PC again: in LiveRepair, run
  `sudo mokutil --delete /usr/share/liverepair/secureboot.cer` (in another Linux, give it the
  disc's `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`), choose a one-time password, restart, press a key
  in the blue screen, and confirm with **Delete MOK**.
- Some PCs (Secured-core PCs, some business laptops) do not trust Microsoft's third-party
  certificate, which shim is signed with, unless it is switched on in the firmware settings (for
  example "Allow Microsoft 3rd Party UEFI CA"). Otherwise, turn Secure Boot off.
- With Secure Boot on, the boot menu has no "UEFI Shell" entry (it is not signed). 32-bit UEFI
  tablets boot only with Secure Boot off.
- Like any current Linux installation medium, shim may add outdated, vulnerable Linux boot
  loaders to the PC's list of blocked ones (SBAT), as Windows updates do too.

## Using it

The LXQt desktop starts on its own, with the **Arch-Colors** theme, its color palette and its
wallpaper, so it is dark throughout: the Qt programs follow the Arch-Colors palette, the GTK
programs and Firefox get the desktop's dark preference, and the window borders and icons are dark
too. Programs that have their own theme setting can still be switched to light. The user is
`live`, without a password; `sudo` and the programs' administrator actions (cloning, recovery,
formatting, S.M.A.R.T.) work without asking for one. Launchers for the programs are on the
desktop, in the panel and in the menu.

The boot menu offers:

- **LiveRepair**: the normal start. From a USB drive, the system copies itself to RAM when there
  is enough memory, so the drive can be removed.
- **copy to RAM (frees the DVD drive)**: copies the system to RAM before starting (4 GB of RAM
  or more), then lets go of the disc, so you can take the DVD out and burn other discs with LinBurn.
- **safe graphics** (`nomodeset`), for machines whose screen stays black or garbled.
- **Memtest86+**, for testing memory before the system starts.

Good to know:

- **Disks are never mounted automatically**, and Linux software-RAID members are never assembled
  on their own, so a failing disk is only read when you ask, and nothing is in use when you clone,
  recover or write to it. Mount disks from the file manager when you need to.
- Wired networks connect by themselves; "Network Connections" in the panel sets up Wi-Fi.
- Files saved in the live system are lost when it shuts down: save images, recovered files and
  reports to a real disk or USB drive.
- `/etc/liverepair-release` lists the version and commit of each program in the ISO.

## What is in the live system

- **Arch Linux** with the latest kernel and the common GPU, Wi-Fi and Ethernet firmware. Every
  program above ships an Arch PKGBUILD, and Arch's repositories carry all of their dependencies.
- **LXQt** on X11, a light Qt 6 desktop, with the file manager, terminal and text editor.
- **Firefox**, NetworkManager, and repair tools: GPT fdisk, parted, TestDisk/PhotoRec, cryptsetup,
  LVM, mdadm, hdparm, efibootmgr.
- The `diskhealthd` service runs, so DiskHealth reads S.M.A.R.T. data right away.

## How it is built and tested

[`build.sh`](build.sh) builds each program into a pacman package with the PKGBUILD from its own
repository, adds the packages to a local package repository, and runs `mkarchiso` on the
[`profile/`](profile) directory (based on archiso's `releng` profile).

Then [`scripts/secureboot.sh`](scripts/secureboot.sh) downloads shim (checking its SHA-256
checksum), builds GRUB for it, signs GRUB, the kernel and Memtest86+ with your key, and puts them,
shim, MokManager and your key's certificate in the ISO, which `mkarchiso` then builds again.

[`scripts/qemu-test.sh`](scripts/qemu-test.sh) boots the ISO in QEMU from an emulated DVD drive:

1. with UEFI firmware, Secure Boot on (with Microsoft's keys, as on PCs) and the ISO's key
   enrolled, running a self-test that checks every program, its tools, services and
   passwordless admin access, does real work with them (a TM5 engine self-test, a verified
   FastCopy copy, a VirtConvert conversion, and ManageDisks partitioning the test disk with HFS+
   and APFS and checking both), and takes a screenshot of each program's window;
2. with Secure Boot on but the key not enrolled, checking that shim refuses to start GRUB and
   starts MokManager instead;
3. with UEFI firmware that has the keys but Secure Boot switched off, checking the desktop and
   the theme;
4. with BIOS firmware, choosing *copy to RAM* in the boot menu, and checking the desktop, the
   theme, and that the DVD is no longer in use.

The boots also check that dark mode reaches Qt, GTK and libadwaita programs.

```sh
scripts/qemu-test.sh out/liverepair-*.iso test-results     # uses KVM when available
```

The [Build ISO](.github/workflows/build-iso.yml) workflow does both on every push. It publishes
nothing; the ISO and the screenshots are kept for a few days as the run's artifacts. (Each run
signs with a new key of its own, which is not kept.)

### Changing the ISO

- Programs: the `apps` list at the top of [`build.sh`](build.sh), plus the package name in
  [`profile/packages.x86_64`](profile/packages.x86_64)
- Tools that are not in Arch's repositories: a PKGBUILD in its own folder under [`packages/`](packages),
  plus the package name in `packages.x86_64`. `build.sh` builds every folder there.
- Other packages: [`profile/packages.x86_64`](profile/packages.x86_64)
- Desktop defaults (theme, panel, file manager, session): [`profile/airootfs/etc/skel`](profile/airootfs/etc/skel)
- The live user, autologin and permissions: [`profile/airootfs`](profile/airootfs)
  (`usr/local/bin/liverepair-mkuser`, `etc/polkit-1/rules.d`, `etc/sudoers.d`)
- Boot menus: [`profile/grub/grub.cfg`](profile/grub/grub.cfg) (UEFI), [`profile/syslinux`](profile/syslinux) (BIOS).
  UEFI boots with GRUB rather than systemd-boot so that the ISO also boots from a DVD on real PCs:
  systemd-boot needs the kernel inside the El Torito boot image, which then outgrows what the boot
  catalog can describe (32 MiB), and many PCs stop with "Error opening root path: Device error".
  `build.sh` checks this and fails if it ever happens again.
- Dark mode: the `[Palette]` in [`lxqt.conf`](profile/airootfs/etc/skel/.config/lxqt/lxqt.conf) (Qt),
  [`90_liverepair.gschema.override`](profile/airootfs/usr/share/glib-2.0/schemas/90_liverepair.gschema.override)
  (GTK, libadwaita, Firefox, through xdg-desktop-portal), and the Openbox theme in
  [`usr/share/themes`](profile/airootfs/usr/share/themes)
- BIOS boot menu background: [`tools/make-artwork.py`](tools/make-artwork.py)
- Secure Boot (shim version, GRUB's modules): [`scripts/secureboot.sh`](scripts/secureboot.sh).
  With Secure Boot on, GRUB cannot load modules, so every one that the boot menus use must be in
  its list.
