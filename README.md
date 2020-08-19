# Shell script for burn-in and testing of drives
## Purpose
`disk-burnin.sh` is a POSIX-compliant shell script I wrote to simplify the process of burning-in disks. It is intended for use only on disks which do not contain data, such as new disks or disks which are being tested or re-purposed. I was inspired by the ["How To: Hard Drive Burn-In Testing"](https://forums.freenas.org/index.php?threads/how-to-hard-drive-burn-in-testing.21451/) thread on the FreeNAS forum and I want to give full props to the good folks who contributed to that thread. 

## Warnings
Be warned that:                                                             
                                                                           
* This script runs the `badblocks` program in destructive mode, which erases any data on the disk. Therefore, please be careful! __Do not run this script on disks containing data you value!__
* Run times for large disks can take several days to a week or more to complete, so it is a good idea to use `tmux` sessions to prevent mishaps.               
* Must be run as 'root', so either log on using the root account or use the `sudo` command, for example: `sudo ./disk_burnin.sh sda`                                          
         
## Tests         
Performs these steps:                                                      
                                                                           
1. Run SMART short test
1. Run `badblocks`                                             
1. Run SMART extended test                                               

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
- `-b 4096` : Use a block size of 4096
- `-e 1` : Abort the test if an error is found (remove this option for full testing of drives)
- `-v` : Verbose mode
- `-o` : Write list of bad blocks found (if any) to a file named `burnin-[model]_[serial number].bb`
- `-s` : Show progress
- `-w` : Write-mode test, writes four patterns (0xaa, 0x55, 0x44, 0x00) on every disk block
                                                                           
The only required command-line argument is the device specifier, e.g.:
                                                                           
`./disk-burnin.sh sda`
                                                                           
...will run the burn-in test on device /dev/sda
                                                                           
## Dry Run Mode

The script supports a 'dry run mode' which lets you check the sleep duration calculations and insure that the sequence of commands suits your needs without actually performing any operations on disks. In 'dry runs' the script does not perform any SMART tests or invoke the `sleep` or `badblocks` programs.

The script was formerly distributed with 'dry run mode' enabled by default, but this is no longer the case. You will have to edit the script and set the `Dry_Run` variable to a non-zero value to enable 'dry runs'.
                            
## `smartctl` Device Type

Some users with atypical hardware environments may need to modify the script and specify the `smartctl` command device type explictly with the `-d` option. User __bcmryan__ reports success using `-d sat` with a Western Digital MyBook 8TB external drive enclosure.

## FreeBSD/FreeNAS Notes

Before using the script on FreeBSD systems (including FreeNAS) you should first execute the `sysctl` command below to alter the kernel's geometry debug flags. This allows `badblocks` to write to the entire disk:

`sysctl kern.geom.debugflags=0x10`

Also note that `badblocks` may issue the following warning under FreeBSD/FreeNAS, which can safely be ignored as it has no effect on testing:

`set_o_direct: Inappropiate ioctl for device`

## Operating System Compatibility

Tested under:                                                              
* FreeNAS 9.10.2-U1 (FreeBSD 10.3-STABLE)
* FreeNAS 11.1-U7 (FreeBSD 11.1-STABLE)
* FreeNAS 11.2-U8 (FreeBSD 11.2-STABLE)
* Ubuntu Server 16.04.2 LTS            
* CentOS 7.0

## Drive Models Tested

The script should run successfully on any SATA disk with SMART capabilities, which includes just about all modern drives. It has been tested on these particular devices: 
* HGST Deskstar NAS, UltraStar, UltraStar He10, and UltraStar He12 models
* Western Digital Gold, Black, and Re models

## Prerequisites
Requires the smartmontools, available at https://www.smartmontools.org     
                                                                           
Uses: `grep`, `pcregrep`, `awk`, `sed`, `tr`, `sleep`, `badblocks`

Tested with the static analysis tool at https://www.shellcheck.net to insure that the code is POSIX-compliant and free of issues.

## Author
Written by Keith Nash, March 2017.
Modified on 19 August 2020.
