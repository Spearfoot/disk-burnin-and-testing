## Shell script for burn-in and testing of drives
`disk-burnin.sh` is a POSIX-compliant shell script I wrote to simplify the process of burning-in disks. It is intended for use only on disks which do not contain data, such as new disks or disks which are being tested or re-purposed. I was inspired by the ["How To: Hard Drive Burn-In Testing"](https://forums.freenas.org/index.php?threads/how-to-hard-drive-burn-in-testing.21451/) thread on the FreeNAS forum and I want to give full props to the good folks who contributed to that thread. 
                                                                           
Be aware that:                                                             
                                                                           
* This script runs the `badblocks` program in destructive mode, which erases any data on the disk. Therefore, please be careful! __Do not run this script on disks containing data you value!__
* Run times for large disks can take several days to complete, so it is a good idea to use tmux sessions to prevent mishaps.               
* Must be run as 'root'.                                                
                                                                           
Performs these steps:                                                      
                                                                           
1. Run SMART short test                                                  
2. Run SMART extended test                                               
3. Run `badblocks`                                                         
4. Run SMART short test                                                  
5. Run SMART extended test                                               
                                                                           
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
                                                                           
You can run the script in 'dry run mode' to check the sleep duration calculations and to insure that the sequence of commands suits your needs. In 'dry runs' the script does not actually perform any SMART tests or invoke the `sleep` or `badblocks` programs. The script is distributed with 'dry runs' enabled, so you will need to edit the `Dry_Run` variable, setting it to 0, in order to actually perform tests on drives.                                                           

Before using the script on FreeBSD systems (including FreeNAS) you must first execute the `sysctl` command below to alter the kernel's geometry debug flags. This allows `badblocks` to write to the entire disk:

`sysctl kern.geom.debugflags=0x10`
                                                                           
Tested under:                                                              
* FreeNAS 9.10.2-U1 (FreeBSD 10.3-STABLE)
* FreeNAS 11.1-U7 (FreeBSD 11.1-STABLE)
* Ubuntu Server 16.04.2 LTS            
* CentOS 7.0
                                                                           
Tested on these drives: 
* Intel DC S3700 SSD
* Intel Model 320 Series SSD
* HGST Deskstar NAS (HDN724040ALE640)
* Hitachi/HGST Ultrastar 7K4000 (HUS724020ALE640)
* Western Digital Re (WD4000FYYZ)
* Western Digital Black (WD6001FZWX)
                                                                           
Requires the smartmontools, available at https://www.smartmontools.org     
                                                                           
Uses: `grep`, `pcregrep`, `awk`, `sed`, `tr`, `sleep`, `badblocks`

Tested with the static analysis tool at https://www.shellcheck.net to insure that the code is POSIX-compliant and free of issues.

Written by Keith Nash, March 2017.                                                                         
