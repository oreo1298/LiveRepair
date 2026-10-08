# LiveRepair

A lightweight live ISO for repairing, cloning and checking computers, with these programs
preinstalled and ready to use:

| Program | Repository | What it does |
|---|---|---|
| **CloneAndRecover** | [CloneAndRecover](https://github.com/oreo1298/CloneAndRecover) | Clone disks (also to smaller ones), image and restore them, rescue failing disks with GNU ddrescue |
| **DiskHealth** | [DiskHealth](https://github.com/oreo1298/DiskHealth) | S.M.A.R.T., health, benchmarks and surface tests for HDDs, SSDs, NVMe and flash drives |
| **LinBurn** | [ImgBurnLinux](https://github.com/oreo1298/ImgBurnLinux) | ImgBurn-style CD/DVD/Blu-ray burning, reading, building and verifying |
| **Rufux** | [WindowsUSBLinux](https://github.com/oreo1298/WindowsUSBLinux) | Rufus-style bootable USB drives from Windows and Linux images |
| **VirtConvert&Create** | [VirtConvert](https://github.com/oreo1298/VirtConvert) | Convert and create virtual disks (VDI, VMDK, VHD, VHDX, QCOW2, OVA) |
| **PC Insurance Report** | [PCInsuranceReport](https://github.com/oreo1298/PCInsuranceReport) | PDF insurance damage reports for computer repairs |

Every prerequisite is included: Qt 6 with PySide6 and PyQt6, ddrescue, partclone, smartmontools,
fio, nvme-cli, qemu-img, wimlib, xorriso, cdrdao, cdrtools, dvd+rw-tools, GRUB, the Rufus UEFI:NTFS
image, ReportLab, Pillow, and the tools for FAT, exFAT, NTFS, ext4, Btrfs, XFS and UDF.

## Download

Get the ISO from [Releases](https://github.com/oreo1298/LiveRepair/releases/latest), then:

1. Write it to a USB drive with Rufux, Rufus (DD mode), balenaEtcher or Ventoy, or with
   `sudo dd if=liverepair-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`. It also burns to a DVD.
2. Boot from it, UEFI or legacy BIOS. **Turn Secure Boot off** first: the ISO is not signed.

The LXQt desktop starts on its own. The user is `live`, without a password; `sudo` and the
programs' administrator actions (cloning, formatting, S.M.A.R.T.) work without asking for one.

The boot menu also offers a *safe graphics* mode (`nomodeset`) for machines whose screen stays
black, and Memtest86+ for testing memory. With enough RAM the system copies itself to memory,
so the USB drive can be removed after booting.

## What is in the live system

- **Arch Linux** with the latest kernel and the common GPU, Wi-Fi and Ethernet firmware.
  Arch was chosen because every program above already ships an Arch PKGBUILD, and Arch's
  repositories carry all of their dependencies at current versions.
- **LXQt** on X11: a light desktop built on the same Qt 6 libraries as the programs.
  Launchers for the programs are on the desktop, in the panel and in the menu.
- File manager, terminal, text editor, the Falkon web browser, and NetworkManager: wired
  networks connect by themselves, and "Network Connections" in the panel sets up Wi-Fi.
- Repair tools: GPT fdisk, parted, TestDisk/PhotoRec, cryptsetup, LVM, hdparm, efibootmgr.
- **Disks are never mounted automatically**, so a failing disk is only read when you ask, and
  nothing is in use when you clone it or write to it. The `diskhealthd` service runs so that
  DiskHealth can read S.M.A.R.T. data right away.

`/etc/liverepair-release` in the live system lists the version and commit of each program.

## How it is built

[`build.sh`](build.sh) builds each program into a pacman package with the PKGBUILD from its own
repository (default branch), adds them to a local package repository, and runs `mkarchiso` on
the [`profile/`](profile) directory (based on archiso's `releng` profile).

The [Build ISO](.github/workflows/build-iso.yml) workflow runs this in an Arch Linux container,
then boots the ISO in QEMU three times: once with a self-test that checks every program and its
tools, services and passwordless admin access, takes a screenshot of each program's window, and
converts a disk image with VirtConvert; and once each with UEFI and BIOS firmware as a user would
boot it. The screenshots are kept as the run's `boot-test-results` artifact.

To publish a new ISO with the latest version of every program: **Actions → Build ISO → Run
workflow**. The release is tagged with the build date (`v2026.10.08`, then `v2026.10.08-2`, …).

### Building it yourself

On Arch Linux, as root (about 10 GB of free space):

```sh
sudo ./build.sh                       # ISO in ./out
```

On any other Linux with Docker or Podman:

```sh
sudo scripts/build-in-docker.sh       # ISO in ./out
```

Build a program from a local checkout instead of GitHub with `APP_SRC_<Repository>=/path`, for
example `sudo APP_SRC_DiskHealth=~/src/DiskHealth ./build.sh`.

Boot-test the result (uses KVM when available):

```sh
scripts/qemu-test.sh out/liverepair-*.iso test-results
```

### Changing the ISO

- Packages: [`profile/packages.x86_64`](profile/packages.x86_64)
- Desktop defaults (panel, file manager, session): [`profile/airootfs/etc/skel`](profile/airootfs/etc/skel)
- The live user, autologin and permissions: [`profile/airootfs`](profile/airootfs)
  (`usr/local/bin/liverepair-mkuser`, `etc/polkit-1/rules.d`, `etc/sudoers.d`)
- Boot menus: [`profile/efiboot`](profile/efiboot) (UEFI), [`profile/syslinux`](profile/syslinux) (BIOS)
- Wallpaper and boot splash: [`tools/make-artwork.py`](tools/make-artwork.py)
- Adding another program: an entry in the `apps` list at the top of [`build.sh`](build.sh) and its
  package name in `packages.x86_64`.
