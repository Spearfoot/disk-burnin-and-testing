# Shell script for burn-in and testing of drives

## Purpose

`disk-burnin.sh` is a POSIX-compliant shell script I wrote to simplify the process of burning-in disks. It is intended for use only on disks which do not contain data, such as new disks or disks which are being tested or re-purposed. I was inspired by the ["How To: Hard Drive Burn-In Testing"](https://forums.freenas.org/index.php?threads/how-to-hard-drive-burn-in-testing.21451/) thread on the FreeNAS forum and I want to give full props to the good folks who contributed to that thread.

## Warnings

Be warned that:

* This script runs `badblocks` in destructive mode, which erases any data on the disk. Therefore, please be careful! __Do not run this script on disks containing valuable data!__
* Run times for large disks can be several days. Use `tmux` or `screen` to test multiple disks in parallel.
* Must be run as 'root'.

## Tests

Performs these steps:

1. Run SMART short test
2. Run `badblocks`
3. Run SMART extended test

The script calls `sleep` after starting each SMART test, using a duration based on the polling interval reported by the disk, after which it polls for test completion.

Full SMART information is pulled after each SMART test. All output except for the `sleep` command is echoed to both the screen and log file.

You should periodically monitor the burn-in progress and check for errors, particularly any errors reported by `badblocks`, or these SMART errors:

|ID|Attribute Name|
|---:|---|
|  5|Reallocated_Sector_Ct|
|196|Reallocated_Event_Count|
|197|Current_Pending_Sector|
|198|Offline_Uncorrectable|

These indicate possible problems with the drive. You therefore may wish to abort the remaining tests and proceed with an RMA exchange for new drives or discard old ones. Also please note that this list is not exhaustive.

The script extracts the drive model and serial number and creates a log filename of the form `burnin-[model]_[serial number].log`.

## `badblocks` Options

`badblocks` is invoked with the following options:

* `-b 8192` : Use a block size of 8192 (override this setting with the `-b` option below)
* `-e 1` : Abort the `badblocks` test immediately if an error is found (override this setting with the `-x` option below)
* `-c 64` : Number of concurrent blocks to check. (override this setting with the `-c` option below, but beware of memory use with high values)
* `-v` : Verbose mode
* `-o` : Write list of bad blocks found (if any) to a file named `burnin-[model]_[serial number].bb`
* `-s` : Show progress
* `-w` : Write-mode test, writes four patterns (0xaa, 0x55, 0xff, 0x00) on every disk block

## Usage

`./disk-burnin.sh [-h] [-e] [-b <block_size>] [-c <num_blocks>] [-f] [-o <directory>] [-x] <disk>`

### Options

* `-h`: show help text
* `-e`: show extended help text
* `-b`: block size (default: 8192)
* `-c`: number of concurrent blocks to check (default: 64). Higher values will use more memory.
* `-f`: run a full, destructive test. Disables the default 'dry-run mode'. **ALL DATA ON THE DISK WILL BE LOST!**
* `-o <directory>`: write log files to `<directory>` (default: working directory `$(pwd)`)
* `-x`: perform a full pass of `badblocks`, using the `-e 0` option.
* `<disk>`: disk to burn-in (`/dev/` may be omitted)

### Examples

* `./disk-burnin.sh sda`: run in dry-run mode on disk `/dev/sda`
* `./disk-burnin.sh -f /dev/sdb`: run full, destructive test on disk `/dev/sdb`
* `./disk-burnin.sh -f -o ~/burn-in-logs sdc`: run full, destructive test on disk `/dev/sdc` and write the log files to `~/burn-in-logs` directory

## Dry-Run Mode

The script runs in dry-run mode by default, so you can check the sleep durations and insure that the sequence of commands suits your needs. In dry-run mode the script does not actually perform any SMART tests or invoke the `sleep` or `badblocks` programs.

In order to perform tests on drives, you will need to provide the `-f` option.

## `smartctl` Device Type

Some users with atypical hardware environments may need to modify the script and specify the `smartctl` command device type explictly with the `-d` option. User __bcmryan__ reports success using `-d sat` with a Western Digital MyBook 8TB external drive enclosure.

## FreeBSD / FreeNAS Notes

Before using the script on FreeBSD systems (including FreeNAS) you must first execute this `sysctl` command to alter the kernel's geometry debug flags. This allows `badblocks` to write to the entire disk:

`sysctl kern.geom.debugflags=0x10`

Also note that `badblocks` may issue the following warning under FreeBSD / FreeNAS, which can safely be ignored as it has no effect on testing:

`set_o_direct: Inappropiate ioctl for device`

## Operating System Compatibility

Tested under:

* FreeNAS 9.10.2-U1 (FreeBSD 10.3-STABLE)
* FreeNAS 11.1-U7 (FreeBSD 11.1-STABLE)
* FreeNAS 11.2-U8 (FreeBSD 11.2-STABLE)
* Ubuntu Server 16.04.2 LTS
* CentOS 7.0
* Tiny Core Linux 11.1
* Fedora 33 Workstation

## Drive Models Tested

The script should run successfully on any SAS or SATA disk with SMART capabilities, which includes just about all modern drives. It has been tested on these particular devices:

* Intel
  * DC S3700 SSD
  * Model 320 Series SSD
* HGST
  * Deskstar NAS (HDN724040ALE640)
  * Ultrastar 7K4000 (HUS724020ALE640)
  * Ultrastar He10
  * Ultrastar He12
* Western Digital
  * Black (WD6001FZWX)
  * Gold
  * Re (WD4000FYYZ)
  * Green
  * Red
  * WD140EDFZ
* Seagate
  * IronWolf NAS HDD 12TB (ST12000VN0008)
  * IronWolf NAS HDD 8TB (ST8000NE001-2M7101)

## Prerequisites

smartmontools, available at [www.smartmontools.org](https://www.smartmontools.org)

Uses: `grep`, `awk`, `sed`, `sleep`, `badblocks`, `smartctl`

Tested with the static analysis tool at [www.shellcheck.net](https://www.shellcheck.net) to insure that the code is POSIX-compliant and free of issues.

## Author

Original author: Keith Nash, March 2017.
Modified on 19 February 2021.
