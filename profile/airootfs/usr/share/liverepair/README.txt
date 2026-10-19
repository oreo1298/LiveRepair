Welcome to LiveRepair
=====================

Everything runs from memory; nothing is installed on this computer.
Disks are never mounted automatically. Use the file manager or the panel's
"Removable media" button to mount one, and unmount it before cloning,
rescuing, or writing to it.

Programs (desktop, panel and the application menu):

  CloneAndRecover        Clone disks (also to smaller ones), image and restore them,
                         rescue failing disks with GNU ddrescue.        CLI: cnrctl
  RecoverAll             Recover deleted files, lost partitions and photos; repair
                         and image disks.                               CLI: recoverctl
  DiskHealth             S.M.A.R.T., health, benchmarks and surface tests
                         for HDDs, SSDs, NVMe and flash drives.         CLI: diskctl
  ManageDisks            Partition and format disks (FAT, exFAT, NTFS, ext4, Btrfs,
                         XFS, F2FS, HFS+, APFS, LUKS).                  CLI: managedisks-cli
  Dendro                 WizTree-style disk space analyzer: which folders, files
                         and file types use the space, with a treemap
                         (WizTreeLinux).
  TM5 for Linux          RAM stability test with TestMem5 configs
                         (Extreme1 by anta777 and others).              CLI: tm5linux-cli
  FastCopy Linux         Fast file copy, sync, move and delete with
                         verification.                                  CLI: fastcopy-linux --no-ui
  LinBurn                ImgBurn-style CD/DVD/Blu-ray burning, reading, building
                         and verifying (ImgBurnLinux).
  Rufux                  Bootable USB drives from Windows and Linux images, like
                         Rufus (WindowsUSBLinux).
  VirtConvert&Create     Convert and create virtual disks (VDI, VMDK, VHD, VHDX,
                         QCOW2, OVA) and write them to real disks.      CLI: virtconvert

Also included: Firefox, file manager, terminal, text editor,
"Network Connections" (Wi-Fi setup; wired networks connect by themselves),
GPT fdisk, parted, TestDisk/PhotoRec, cryptsetup, LVM, smartctl, nvme-cli,
Memtest86+ (boot menu).

Started from a DVD? Choose "copy to RAM" in the boot menu to free the DVD
drive: you can then take the disc out and burn other discs with LinBurn.

The "live" user has no password and can use sudo. Program windows that need
root (cloning, recovery, formatting, S.M.A.R.T.) get it without asking for a
password.

Save your work (images, recovered files) to a real disk or USB drive: files
in the live system are lost when you shut down.

Secure Boot: the ISO's boot loader and kernel are signed with the key of
whoever built it. "mokutil --sb-state" shows whether Secure Boot is on, and
"mokutil --test-key /usr/share/liverepair/secureboot.cer" whether this PC has
that key enrolled. "sudo mokutil --delete /usr/share/liverepair/secureboot.cer"
removes it again (confirm at the next boot, in the blue MokManager screen).

Version information: /etc/liverepair-release
Source: https://github.com/oreo1298/LiveRepair
