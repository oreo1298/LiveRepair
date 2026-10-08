Welcome to LiveRepair
=====================

Everything runs from memory; nothing is installed on this computer.
Disks are never mounted automatically. Use the file manager or the panel's
"Removable media" button to mount one, and unmount it before cloning,
rescuing, or writing to it.

Programs (desktop, panel and the application menu):

  CloneAndRecover        Clone disks (also to smaller ones), image and restore them,
                         rescue failing disks with GNU ddrescue.        CLI: cnrctl
  DiskHealth             S.M.A.R.T., health, benchmarks and surface tests
                         for HDDs, SSDs, NVMe and flash drives.         CLI: diskctl
  LinBurn                ImgBurn-style CD/DVD/Blu-ray burning, reading, building
                         and verifying (ImgBurnLinux).
  Rufux                  Bootable USB drives from Windows and Linux images, like
                         Rufus (WindowsUSBLinux).
  VirtConvert&Create     Convert and create virtual disks (VDI, VMDK, VHD, VHDX,
                         QCOW2, OVA) and write them to real disks.      CLI: virtconvert
  PC Insurance Report    PDF insurance damage reports for computer repairs.

Also included: file manager, terminal, Falkon web browser, text editor,
GPT fdisk, parted, TestDisk/PhotoRec, cryptsetup, LVM, smartctl, nvme-cli,
Memtest86+ (boot menu).

The "live" user has no password and can use sudo. Program windows that need
root (cloning, formatting, S.M.A.R.T.) get it without asking for a password.

Save your work (images, reports) to a real disk or USB drive: files in the
live system are lost when you shut down.

Version information: /etc/liverepair-release
Source: https://github.com/oreo1298/LiveRepair
