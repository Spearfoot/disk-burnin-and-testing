#!/usr/bin/env bash
########################################################################
#
# disk-burnin.sh
#
# A script to simplify the process of burning-in disks. Intended for use
# only on disks which do not contain valuable data, such as new disks or
# disks which are being tested or re-purposed.
#
# Be aware that:
#
#   1> This script runs the badblocks program in destructive mode, which
#      erases any data on the disk.
#
#   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#   !!!!!        WILL DESTROY THE DISK CONTENTS! BE CAREFUL!        !!!!!
#   !!!!! DO NOT RUN THIS SCRIPT ON DISKS CONTAINING DATA YOU VALUE !!!!!
#   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
#   2> Run times for large disks can take several days to complete, so it
#      is a good idea to use tmux sessions to prevent mishaps. 
#
#   3> Must be run as 'root'.
#
# Performs these steps:
#
#   1> Run SMART short test
#   2> Run SMART extended test
#   3> Run badblocks
#   4> Run SMART short test
#   5> Run SMART extended test
#
# The script sleeps after starting each SMART test, using a duration 
# based on the polling interval reported by the disk, and adding an
# additional delay defined below to account for discrepancies.
#
# Full SMART information is pulled after each SMART test. All output
# except for the sleep command is echoed to both the screen and log file.
#
# You should monitor the burn-in progress and watch for errors, particularly
# any errors reported by badblocks, or these SMART errors:
#
#   5 Reallocated_Sector_Ct   
# 196 Reallocated_Event_Count 
# 197 Current_Pending_Sector  
# 198 Offline_Uncorrectable   
#
# These indicate possible problems with the drive. You therefore may
# wish to abort the remaining tests and proceed with an RMA exchange
# for new drives or discard old ones. Also please note that this list
# is not exhaustive.
#
# The script extracts the drive model and serial number and forms
# a log filename of the form 'burnin-[model]_[serial number].log'.
#
# badblocks is invoked with a block size of 4096, the -wsv options, and
# the -o option to instruct it to write the list of bad blocks found (if
# any) to a file named 'burnin-[model]_[serial number].bb'. 
# 
# The only required command-line argument is the device specifier, e.g.:
#
#   ./disk-burnin.sh sda 
#
# ...will run the burn-in test on device /dev/sda
#
# You can run the script in 'dry run mode' (see below) to check the sleep
# duration calculations and to insure that the sequence of commands suits
# your needs. In 'dry runs' the script does not actually perform any 
# SMART tests or invoke the sleep or badblocks programs. The script is
# distributed with 'dry runs' enabled, so you will need to edit the
# Dry_Run variable below, setting it to 0, in order to actually perform
# tests on drives.
# 
# Before using the script on FreeBSD systems (including FreeNAS) you must
# first execute this sysctl command to alter the kernel's geometry debug
# flags. This allows badblocks to write to the entire disk:
#
#   sysctl kern.geom.debugflags=0x10
# 
# Tested under:
#   FreeNAS 9.10.2 (FreeBSD 10.3-STABLE)
#   Ubuntu Server 16.04.2 LTS
#
# Tested on:
#   Intel DC S3700 SSD
#   Intel Model 320 Series SSD
#   HGST Deskstar NAS (HDN724040ALE640)
#   Hitachi/HGST Ultrastar 7K4000 (HUS724020ALE640)
#   Western Digital Re (WD4000FYYZ)
#   Western Digital Black (WD6001FZWX)
#
# Requires the smartmontools, available at https://www.smartmontools.org
#
# Uses: grep, pcregrep, awk, sed, tr, sleep, badblocks
#
# Written by Keith Nash, March 2017
#
########################################################################

if [ $# -ne 1 ]; then
  echo "Error: not enough arguments!"
  echo "Usage is: $0 drive_device_specifier"
  exit 2
fi

Drive=$1

# Set Dry_Run to a non-zero value to test out the script without actually
# running any tests: set it to zero when you are ready to burn-in disks.

Dry_Run=1

# Constants, in seconds, added to the short and extended test sleep duration.
# Edit to suit your needs and environment:

Short_Test_Extra_Delay=30
Extended_Test_Extra_Delay=300

# Directory specifiers for log and badblocks data files. Leave off the 
# trailing slash:

Log_Dir="."
BB_Dir="."

########################################################################
#
# Prologue
#
########################################################################

Host_Name=$(hostname -s)

# Obtain the disk model and serial number:

Disk_Model=$(smartctl -i /dev/${Drive} | grep "Device Model" | awk '{print $3, $4, $5}' | sed -e 's/^[ \t]*//;s/[ \t]*$//')

if [ -z "$Disk_Model" ]; then
  Disk_Model=$(smartctl -i /dev/${Drive} | grep "Model Family" | awk '{print $3, $4, $5}' | sed -e 's/^[ \t]*//;s/[ \t]*$//')
fi

Disk_Model=$(tr ' ' '_' <<< ${Disk_Model})

Serial_Number=$(smartctl -i /dev/${Drive} | grep "Serial Number" | awk '{print $3}')

Serial_Number=$(tr ' ' '-' <<< ${Serial_Number})

# Form the log and bad blocks data filenames:

Log_File=$(tr ' ' '-' <<< "burnin-${Disk_Model}_${Serial_Number}.log")
Log_File=$(tr -s '-' <<< ${Log_File})
Log_File=$(tr -s '_' <<< ${Log_File})
Log_File=$Log_Dir/$Log_File

BB_File=$(tr ' ' '-' <<< "burnin-${Disk_Model}_${Serial_Number}.bb")
BB_File=$(tr -s '-' <<< ${BB_File})
BB_File=$(tr -s '_' <<< ${BB_File})
BB_File=$BB_Dir/$BB_File

# Query the short and extended test duration, in minutes. Use the values to
# caculate how long we should sleep after starting the SMART tests:

Short_Test_Minutes=$(smartctl -a /dev/${Drive} | pcregrep -M "Short self-test routine.*\n.*recommended polling time:" | awk '{print $5}' | sed -e 's/)//' | tr -d '\n')

Extended_Test_Minutes=$(smartctl -a /dev/${Drive} | pcregrep -M "Extended self-test routine.*\n.*recommended polling time:" | awk '{print $5}' | sed -e 's/)//' | tr -d '\n')

# If the extended test duration is short (less than 60 minutes), assume we have
# an SSD and set the extended test delay the same as the short test delay:

if (( $Extended_Test_Minutes < 60 )); then
  Extended_Test_Extra_Delay=$Short_Test_Extra_Delay
fi

Short_Test_Sleep=$((Short_Test_Minutes*60+Short_Test_Extra_Delay))
Extended_Test_Sleep=$((Extended_Test_Minutes*60+Extended_Test_Extra_Delay))

########################################################################
#
# Local functions
#
########################################################################

echo_str()
{
  echo $1 | tee -a ${Log_File}
}

push_header()
{
  echo_str "+-----------------------------------------------------------------------------"
}

run_short_test()
{
  push_header
  echo_str "+ Run SMART short test on drive /dev/${Drive}: $(date)"
  push_header
  if (( $Dry_Run == 0 )); then
    smartctl -t short /dev/$Drive | tee -a ${Log_File}
    echo_str "Sleep ${Short_Test_Sleep} seconds until the short test finishes"
    sleep ${Short_Test_Sleep}
    smartctl -a /dev/$Drive | tee -a ${Log_File}
  else
    echo_str "Dry run: would start the SMART short test and sleep ${Short_Test_Sleep} seconds until the test finishes"
  fi
  echo_str "Finished SMART short test on drive /dev/${Drive}: $(date)"
}

run_extended_test()
{
  push_header
  echo_str "+ Run SMART extended test on drive /dev/${Drive}: $(date)"
  push_header
  if (( $Dry_Run == 0 )); then
    smartctl -t long /dev/$Drive | tee -a ${Log_File}
    echo_str "Sleep ${Extended_Test_Sleep} seconds until the long test finishes"
    sleep ${Extended_Test_Sleep}
    smartctl -a /dev/$Drive | tee -a ${Log_File}
  else
    echo_str "Dry run: would start the SMART extended test and sleep ${Extended_Test_Sleep} seconds until the test finishes"
  fi
  echo_str "Finished SMART extended test on drive /dev/${Drive}: $(date)"
}

run_badblocks_test()
{
  push_header
  echo_str "+ Run badblocks test on drive /dev/${Drive}: $(date)"
  push_header
  if (( $Dry_Run == 0 )); then
#
#   This is the command which erases all data on the disk:
#
    badblocks -b 4096 -wsv -o ${BB_File} /dev/$Drive | tee -a ${Log_File}
  else
    echo_str "Dry run: would run badblocks -b 4096 -wsv -o ${BB_File} /dev/${Drive}"
  fi
  echo_str "Finished badblocks test on drive /dev/${Drive}: $(date)"
}

########################################################################
#
# Action begins here
#
########################################################################

rm $Log_File
push_header
echo_str "+ Started burn-in of /dev/${Drive} on ${Host_Name} : $(date)"
push_header

echo_str "Drive Model: ${Disk_Model}"
echo_str "Serial Number: ${Serial_Number}"
echo_str "Short test duration: ${Short_Test_Minutes} minutes"
echo_str "Short test sleep duration: ${Short_Test_Sleep} seconds (includes extra delay of ${Short_Test_Extra_Delay} seconds)"
echo_str "Extended test duration: ${Extended_Test_Minutes} minutes"
echo_str "Extended test sleep duration: ${Extended_Test_Sleep} seconds (includes extra delay of ${Extended_Test_Extra_Delay} seconds)"
echo_str "Log file: ${Log_File}"
echo_str "Bad blocks file: ${BB_File}"

run_short_test
run_extended_test
run_badblocks_test
run_short_test
run_extended_test

push_header
echo_str "+ Finished burn-in of /dev/${Drive} on ${Host_Name} : $(date)"
push_header