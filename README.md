## Shell script for burn-in and testing of drives
`disk-burnin.sh` is a POSIX-compliant shell script I wrote to simplify the process of burning-in disks. It is intended for use only on disks which do not contain data, such as new disks or disks which are being tested or re-purposed. I was inspired by the ["How To: Hard Drive Burn-In Testing"](https://forums.freenas.org/index.php?threads/how-to-hard-drive-burn-in-testing.21451/) thread on the FreeNAS forum and I want to give full props to the good folks who contributed to that thread. 
                                                                           
Be aware that:                                                             
                                                                           
* This script runs the `badblocks` program in destructive mode, which erases any data on the disk. Therefore, please be careful! __Do not run this script on disks containing data you value!__
* You will need to edit the script and change the `Dry_Run` variable, setting it to 0, in order to actually perform tests on drives (see details below).  
* Run times for large disks can take several days to a week or more to complete, so it is a good idea to use tmux sessions to prevent mishaps.               
* Must be run as 'root', so either log on using the root account or use the `sudo` command, for example: `sudo ./disk_burnin.sh sda`                                          
                                                                           
Performs these steps:                                                      
                                                                           
1. Run SMART short test                                                  
2. Run SMART extended test                                               
3. Run `badblocks`                                                         
4. Run SMART short test                                                  
5. Run SMART extended test                                               

I often skip the second step ("2. Run SMART extended test"); you can do the same by deleting or commenting out the call to ``run_extended_test`` at line 324 in the script. 

The script sleeps after starting each SMART test, using a duration based on the polling interval reported by the disk, and adding an additional delay to account for discrepancies.               
                                                                           
Full SMART information is pulled after each SMART test. All output except for the sleep command is echoed to both the screen and log file.    
                                                                           
You should periodically monitor the burn-in progress and check for errors, particularly any errors reported by badblocks, or these SMART errors:                   
  
|ID|Attribute Name|
|---:|---|
|  5|Reallocated_Sector_Ct|
|196|Reallocated_Event_Count|
|197|Current_Pending_Sector|
|198|Offline_Uncorrectable|
                                                                           
These indicate possible problems with the drive. You therefore may wish to abort the remaining tests and proceed with an RMA exchange for new drives or discard old ones. Also please note that this list is not exhaustive.
                                                                           
The script extracts the drive model and serial number and creates a log filename of the form `burnin-[model]_[serial number].log`.
                                                                           
`badblocks` is invoked with a block size of 4096, the -wsv options, and the -o option to instruct it to write the list of bad blocks found (if any) to a file named `burnin-[model]_[serial number].bb`.
                                                                           
The only required command-line argument is the device specifier, e.g.:
                                                                           
`./disk-burnin.sh sda`
                                                                           
...will run the burn-in test on device /dev/sda
                                                                           
__IMPORTANT: Dry Run is the default__

The script is distributed with 'dry run mode' enabled. This lets you check the sleep duration calculations and to insure that the sequence of commands suits your needs. In 'dry runs' the script does not actually perform any SMART tests or invoke the `sleep` or `badblocks` programs. __Again, you will need to edit the script and change the `Dry_Run` variable, setting it to 0, in order to actually perform tests on drives.__                                                           

Some users with atypical hardware environments may need to modify the script and specify the `smartctl` command device type explictly with the `-d` option. User __bcmryan__ reports success using `-d sat` with a Western Digital MyBook 8TB external drive enclosure.

__FREEBSD/FREENAS NOTES:__

Before using the script on FreeBSD systems (including FreeNAS) you should first execute the `sysctl` command below to alter the kernel's geometry debug flags. This allows `badblocks` to write to the entire disk:

`sysctl kern.geom.debugflags=0x10`

Also note that `badblocks` may issue the following warning under FreeBSD/FreeNAS, which can safely be ignored as it has no effect on testing:

`set_o_direct: Inappropiate ioctl for device`

__OPERATING SYSTEMS__

Tested under:                                                              
* FreeNAS 9.10.2-U1 (FreeBSD 10.3-STABLE)
* FreeNAS 11.1-U7 (FreeBSD 11.1-STABLE)
* FreeNAS 11.2-U8 (FreeBSD 11.2-STABLE)
* Ubuntu Server 16.04.2 LTS            
* CentOS 7.0

__DRIVE MODELS__

The script should run successfully on any SATA disk with SMART capabilities, which includes just about all modern drives. It has been tested on these particular devices: 
* HGST Deskstar NAS, UltraStar, UltraStar He10, and UltraStar He12 models
* Western Digital Gold, Black, and Re models
                                                                           
Requires the smartmontools, available at https://www.smartmontools.org     
                                                                           
Uses: `grep`, `pcregrep`, `awk`, `sed`, `tr`, `sleep`, `badblocks`

Tested with the static analysis tool at https://www.shellcheck.net to insure that the code is POSIX-compliant and free of issues.

Written by Keith Nash, March 2017.
Modified by Yifan Liao and dak180.
Updated on 20 June 2020.
