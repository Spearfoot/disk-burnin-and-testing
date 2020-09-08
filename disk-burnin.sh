#!/bin/sh
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
#   4> Tests of large drives can take days to complete: use tmux!
#
# Performs these steps:
#
#   1> Run SMART short test
#   2> Run badblocks
#   3> Run SMART extended test
#
# The script sleeps after starting each SMART test, using a duration
# based on the polling interval reported by the disk, after which the
# script will poll the disk to verify the self-test has completed.
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
# Uses: grep, awk, sed, sleep, badblocks
#
# Written by Keith Nash, March 2017
#
# KN, 8 Apr 2017:
#   Added minimum test durations because some devices don't return accurate values.
#   Added code to clean up the log file, removing copyright notices, etc.
#   No longer echo 'smartctl -t' output to log file as it imparts no useful information.
#   Emit test results after tests instead of full 'smartctl -a' output.
#   Emit full 'smartctl -x' output at the end of all testing.
#   Minor changes to log output and formatting.
#
# KN, 12 May 2017:
#   Added code to poll the disk and check for completed self-tests.
#
#   As noted above, some disks don't report accurate values for the short and extended
#   self-test intervals, sometimes by a significant amount. The original approach using
#   'fudge' factors wasn't reliable and the script would finish even though the SMART
#   self-tests had not completed. The new polling code helps insure that this doesn't
#   happen.
#
#   Fixed code to work around annoying differences between sed's behavior on Linux and
#   FreeBSD.
#
# KN, 8 Jun 2017
#   Modified parsing of short and extended test durations to accommodate the values
#   returned by larger drives; we needed to strip out the '(' and ')' characters
#   surrounding the integer value in order to fetch it reliably.
#
# KN, 19 Aug 2020
#	Changed Dry_Run value so that dry runs are no longer the default setting.
#	Changed badblocks call to exit immediately on first error.
#	Set logging directoryto current working directory using pwd command.
#	Reduced default tests so that we run:
#		1> Short SMART test
#		2> badblocks
#		3> Extended SMART test
#
########################################################################

# Check required dependencies
readonly DEPENDENCIES="awk badblocks grep sed sleep"
for dependency in ${DEPENDENCIES}; do
  if ! command -v "${dependency}" > /dev/null 2>&1 ; then
    echo "Command '${dependency}' not found. Exiting ..."
    exit 2
  fi
done

# Check script arguments
if [ $# -ne 1 ]; then
  echo "Error: not enough arguments!"
  echo "Usage is: $0 drive_device_specifier"
  exit 2
fi

# Drive to burn-in
readonly Drive="$1"

# Set Dry_Run to a non-zero value to test out the script without actually
# running any tests; leave it set to zero to burn-in disks.
readonly Dry_Run=0

# Directory specifiers for log and badblocks data files. Leave off the trailing
# slash if you specify a value. Default is the current working directory.
readonly Log_Dir="$(pwd)"
readonly BB_Dir="$(pwd)"

# Alternative:
#readonly Log_Dir="."
#readonly BB_Dir="."

########################################################################
#
# Prologue
#
########################################################################

# SMART static information
readonly SMART_INFO="$(smartctl --info "/dev/${Drive}")"
readonly SMART_CAPABILITIES="$(smartctl --capabilities "/dev/${Drive}")"

##################################################
# Get SMART information value.
# Globals:
#   SMART_INFO
# Arguments:
#   value identifier:
#     !!! Only TWO WORD indentifiers are supported !!!
#     !!! Querying e.g. "ATA Version is" will fail !!!
#     - Device Model
#     - Model Family
#     - Serial Number
# Outputs:
#   Write value to stdout.
##################################################
get_smart_info_value() {
  # $1=$2="";                     select all but first two columns
  # gsub(/^[ \t]+|[ \t]+$/, "");  replace leading and trailing whitespace
  # gsub(/ /, "_");               replace remaining spaces with underscores
  # printf $1                     print result without newline at the end
  printf '%s' "${SMART_INFO}" \
    | grep "$1" \
    | awk '{$1=$2=""; gsub(/^[ \t]+|[ \t]+$/, ""); gsub(/ /, "_"); printf $1}'
}

# Get disk model
Disk_Model="$(get_smart_info_value "Device Model")"
[ -z "${Disk_Model}" ] && Disk_Model="$(get_smart_info_value "Model Family")"
readonly Disk_Model

# Get disk serial number
readonly Serial_Number="$(get_smart_info_value "Serial Number")"

# Form the log and bad blocks data filenames:
readonly Log_File="${Log_Dir}/burnin-${Disk_Model}_${Serial_Number}.log"
readonly BB_File="${BB_Dir}/burnin-${Disk_Model}_${Serial_Number}.bb"

##################################################
# Get SMART recommended test duration, in minutes.
# Globals:
#   SMART_CAPABILITIES
# Arguments:
#   test type:
#     - Short
#     - Extended
#     - Conveyance
# Outputs:
#   Write duration to stdout.
##################################################
get_smart_test_duration() {
  # '/'"$1"' self-test routine/   match duration depending on test type arg
  # getline;                      jump to next line
  # gsub(/\(|\)/, "");            remove parantheses
  # printf $4                     print 4th column without newline at the end
  printf '%s' "${SMART_CAPABILITIES}" \
    | awk '/'"$1"' self-test routine/{getline; gsub(/\(|\)/, ""); printf $4}'
}

# The script initially sleeps for a duration after a test is started.
# Afterwards the completion status is repeatedly polled.

# SMART short test duration
readonly Short_Test_Minutes="$(get_smart_test_duration "Short")"
readonly Short_Test_Seconds="$(( Short_Test_Minutes * 60))"

# SMART extended test duration
readonly Extended_Test_Minutes="$(get_smart_test_duration "Extended")"
readonly Extended_Test_Seconds="$(( Extended_Test_Minutes * 60 ))"

# Maximum duration the completion status is polled
readonly Poll_Timeout_Hours=4
readonly Poll_Timeout_Seconds="$(( Poll_Timeout_Hours * 60 * 60))"

# Sleep interval between completion status polls
readonly Poll_Interval_Seconds=15

########################################################################
#
# Local functions
#
########################################################################

##################################################
# Log informational message.
# Globals:
#   Log_File
# Arguments:
#   Message to log.
# Outputs:
#   Write message to stdout and log file.
##################################################
log_info()
{
  now="$(date +"%F %T %Z")"
  printf "%s\n" "[${now}] $1" | tee -a "${Log_File}"
}

##################################################
# Log emphasized header message.
# Arguments:
#   Message to log.
##################################################
log_header()
{
  log_info "+-----------------------------------------------------------------------------"
  log_info "+ $1"
  log_info "+-----------------------------------------------------------------------------"
}

##################################################
# Poll repeatedly whether SMART self-test has completed.
# Globals:
#   Drive
#   Poll_Interval_Seconds
#   Poll_Timeout_Seconds
# Arguments:
#   None
# Returns:
#   0 if success or failure.
#   1 if timeout threshold exceeded.
##################################################
poll_selftest_complete()
{
  l_poll_duration_seconds=0
  while [ "${l_poll_duration_seconds}" -lt "${Poll_Timeout_Seconds}" ]; do
    smartctl --all "/dev/${Drive}" | grep -i "The previous self-test routine completed" > /dev/null 2<&1
    l_status="$?"
    if [ "${l_status}" -eq 0 ]; then
      log_info "SMART self-test succeeded"
      return 0
    fi
    smartctl --all "/dev/${Drive}" | grep -i "of the test failed." > /dev/null 2<&1
    l_status="$?"
    if [ "${l_status}" -eq 0 ]; then
      log_info "SMART self-test failed"
      return 0
    fi
    sleep "${Poll_Interval_Seconds}"
    l_poll_duration_seconds="$(( l_poll_duration_seconds + Poll_Interval_Seconds ))"
  done
  log_info "SMART self-test timeout threshold exceeded"
  return 1
}

##################################################
# Run SMART test and log results.
# Globals:
#   Drive
#   Log_File
# Arguments:
#   Test type:
#     - short
#     - long
#   Test duration in seconds.
##################################################
run_smart_test()
{
  log_header "Run SMART $1 test on drive /dev/${Drive}"
  if [ "${Dry_Run}" -eq 0 ]; then
    smartctl --test="$1" --captive "/dev/${Drive}"
    log_info "SMART $1 test started, awaiting completion for $2 seconds ..."
    sleep "$2"
    poll_selftest_complete
    smartctl --log=selftest "/dev/${Drive}" | tee -a "${Log_File}"
  else
    log_info "Dry run: would start the SMART $1 test and sleep $2 seconds until the test finishes"
  fi
  log_info "Finished SMART short test on drive /dev/${Drive}"
}

##################################################
# Run badblocks test.
# !!! THIS WILL ERASE ALL DATA ON THE DISK !!!!
# Globals:
#   BB_File
#   Drive
# Arguments:
#   None
##################################################
run_badblocks_test()
{
  log_header "Run badblocks test on drive /dev/${Drive}"
  if [ "${Dry_Run}" -eq 0 ]; then
    badblocks -b 4096 -wsv -e 1 -o "${BB_File}" "/dev/${Drive}"
  else
    log_info "Dry run: would run badblocks -b 4096 -wsv -e 1 -o ${BB_File} /dev/${Drive}"
  fi
  log_info "Finished badblocks test on drive /dev/${Drive}"
}

########################################################################
#
# Action begins here
#
########################################################################

if [ -e "$Log_File" ]; then
  rm "$Log_File"
fi

log_header "Started burn-in of /dev/${Drive}"

log_info "Host: $(hostname)"
log_info "Drive Model: ${Disk_Model}"
log_info "Serial Number: ${Serial_Number}"
log_info "Short test duration: ${Short_Test_Minutes} minutes"
log_info "Short test sleep duration: ${Short_Test_Seconds} seconds"
log_info "Extended test duration: ${Extended_Test_Minutes} minutes"
log_info "Extended test sleep duration: ${Extended_Test_Seconds} seconds"
log_info "Log file: ${Log_File}"
log_info "Bad blocks file: ${BB_File}"

# Run the test sequence:
run_smart_test "short" "${Short_Test_Seconds}"
run_badblocks_test
run_smart_test "long" "${Extended_Test_Seconds}"

# Emit full device information to log:
log_header "SMART information for drive /dev/${Drive}"
smartctl --xall --vendorattribute=7,hex48 "/dev/${Drive}" | tee -a "$Log_File"

log_header "Finished burn-in of /dev/${Drive}"

# Clean up the log file:

osflavor="$(uname)"

if [ "${osflavor}" = "Linux" ]; then
  sed -i -e '/Copyright/d' "${Log_File}"
  sed -i -e '/=== START OF READ/d' "${Log_File}"
  sed -i -e '/SMART Attributes Data/d' "${Log_File}"
  sed -i -e '/Vendor Specific SMART/d' "${Log_File}"
  sed -i -e '/SMART Error Log Version/d' "${Log_File}"
fi

if [ "${osflavor}" = "FreeBSD" ]; then
  sed -i '' -e '/Copyright/d' "${Log_File}"
  sed -i '' -e '/=== START OF READ/d' "${Log_File}"
  sed -i '' -e '/SMART Attributes Data/d' "${Log_File}"
  sed -i '' -e '/Vendor Specific SMART/d' "${Log_File}"
  sed -i '' -e '/SMART Error Log Version/d' "${Log_File}"
fi
