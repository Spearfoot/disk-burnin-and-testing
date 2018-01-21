#!/bin/bash
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
# 	1> This script runs the badblocks program in destructive mode, 
# 	which erases any data on the disk.
#
# 	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# 	!!!        WILL DESTROY THE DISK CONTENTS! BE CAREFUL!        !!!
# 	!!! DO NOT RUN THIS SCRIPT ON DISKS CONTAINING DATA YOU VALUE !!!
# 	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# 	2> Run times for large disks can take several days to complete, so
# 	it is a good idea to use tmux sessions to prevent mishaps.
#
# 	3> Must be run as 'root'.
#
# 	4> Tests of large drives can take days to complete: use tmux!
#
# Performs these steps:
#
# 	1> Run SMART short test
# 	2> Run SMART extended test
# 	3> Run badblocks
# 	4> Run SMART short test
# 	5> Run SMART extended test
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
# 	5 Reallocated_Sector_Ct
# 196 Reallocated_Event_Count
# 197 Current_Pending_Sector
# 198 Offline_Uncorrectable
#
# These indicate possible problems with the drive. You therefore may
# wish to abort the remaining tests and proceed with an RMA exchange
# for new drives or discard old ones. Also please note that this list
# is not exhaustive.
#
# The script extracts the drive model and serial number and forms a
# log filename of the form 'burnin-[model]_[serial number].log'.
#
# badblocks is invoked with a block size of 4096, the -wsv options,
# and the -o option to instruct it to write the list of bad blocks
# found (if any) to a file named 'burnin-[model]_[serial number].bb'.
#
# The only required command-line argument is the device specifier,
# e.g.:
#
# 	./disk-burnin.sh sda
#
# ...will run the burn-in test on device /dev/sda
#
# You can run the script in 'dry run mode' (see below) to check the
# sleep duration calculations and to insure that the sequence of
# commands suits your needs. In 'dry runs' the script does not
# actually perform any SMART tests or invoke the sleep or badblocks
# programs. The script is distributed with 'dry runs' enabled, so you
# will need to edit the Dry_Run variable below, setting it to 0, in
# order to actually perform tests on drives.
#
# Before using the script on FreeBSD systems (including FreeNAS) you
# must first execute this sysctl command to alter the kernel's
# geometry debug flags. This allows badblocks to write to the entire
# disk:
#
# 	sysctl kern.geom.debugflags=0x10
#
# Tested under:
# 	FreeNAS 9.10.2 (FreeBSD 10.3-STABLE)
# 	Ubuntu Server 16.04.2 LTS
#
# Tested on:
# 	Intel DC S3700 SSD
# 	Intel Model 320 Series SSD
# 	HGST Deskstar NAS (HDN724040ALE640)
# 	Hitachi/HGST Ultrastar 7K4000 (HUS724020ALE640)
# 	Western Digital Re (WD4000FYYZ)
# 	Western Digital Black (WD6001FZWX)
#
# Requires the smartmontools, available at https://www.smartmontools.org
#
# Uses: grep, pcregrep, awk, sed, tr, sleep, badblocks
#
# Written by Keith Nash, March 2017
#
# KN, 8 Apr 2017:
# 	Added minimum test durations because some devices don't return
# 	accurate values.
# 	Added code to clean up the log file, removing copyright notices,
# 	etc.
# 	No longer echo 'smartctl -t' output to log file as it imparts no
# 	useful information.
# 	Emit test results after tests instead of full
# 	'smartctl -a' output.
# 	Emit full 'smartctl -x' output at the end of all testing.
# 	Minor changes to log output and formatting.
#
# KN, 12 May 2017:
# 	Added code to poll the disk and check for completed self-tests.
#
# 	As noted above, some disks don't report accurate values for the
# 	short and extended self-test intervals, sometimes by a significant
# 	amount. The original approach using 'fudge' factors wasn't
# 	reliable and the script would finish even though the SMART
# 	self-tests had not completed. The new polling code helps insure
# 	that this doesn't happen.
#
# 	Fixed code to work around annoying differences between sed's
# 	behavior on Linux and FreeBSD.
#
# KN, 8 Jun 2017
#
# Modified by Yifan Liao
# 	Modified parsing of short and extended test durations to
# 	accommodate the values returned by larger drives; we needed to
# 	strip out the '(' and ')' characters surrounding the integer value
# 	in order to fetch it reliably.
#
########################################################################

dbUsage() {
	tee >&2 << EOF
Usage: ${0} [-h] [-t] [-l directory] [-b directory] -d drive-device-specifier
Run SMART tests and burn-in tests on a drive.
...

Options:
-h
	Display this help and exit

-t
	Needed to actually run the tests, By default ${0} will just do a dry run.

-d
	Drive Device Specifier.

-l
	Log files directory

-b
	Bad blocks files directory
...
EOF
}

Log_Dir="."
BB_Dir="."
Dry_Run=1

while getopts ":d:l:b:th" OPTION; do
	case "${OPTION}" in
		d)
			driveID="${OPTARG}"
		;;
		l)
			Log_Dir="${OPTARG}"
		;;
		b)
			BB_Dir="${OPTARG}"
		;;
		t)
			Dry_Run=0
		;;
		h | ?)
			dbUsage
			exit 0
		;;
	esac
done

if [ ! -z "${driveID}" ]; then
	echo "error: No Drive Device Specifier." 1>&2
	dbUsage
	exit 4
fi



######################################################################
#
# Prologue
#
######################################################################


SMART_capabilities="$(smartctl -c "/dev/${driveID}")"

SMART_info="$(smartctl -i "/dev/${driveID}")"

# Obtain the disk model:

Disk_Model="$(echo "${SMART_info}" | grep "Device Model" | awk '{print $3, $4, $5}' | sed -e 's:^[ \t]*::' -e 's:[ \t]*$::' | sed -e 's: :_:')"

if [ -z "$Disk_Model" ]; then
  Disk_Model="$(echo "${SMART_info}" | grep "Model Family" | awk '{print $3, $4, $5}' | sed -e 's:^[ \t]*::' -e 's:[ \t]*$::' | sed -e 's: :_:')"
fi

# Obtain the disk serial number:

Serial_Number="$(echo "${SMART_info}"  | grep "Serial Number" | awk '{print $3}' | sed -e 's: :_:')"

# Test to see if disk is a SSD:

if echo "${SMART_info}" | grep "Rotation Rate:" | grep -q "Solid State Device"; then
	driveType="ssd"
fi

# Test to see if it is necessary to specify connection type:

SMART_deviceType="$(smartctl -d test "/dev/${driveID}")"

if echo "${SMART_deviceType}" | grep -q "Device open changed type"; then
	if echo "${SMART_deviceType}" | grep -q "[SAT]:"; then
		driveConnectionType="sat,auto"
	fi
else
	driveConnectionType="auto"
fi


# Form the log and bad blocks data filenames:

Log_File="burnin-${Disk_Model}_${Serial_Number}-$(date -u +%Y%m%d-%H%M+0).log"
Log_File="${Log_Dir}/${Log_File}"

BB_File="burnin-${Disk_Model}_${Serial_Number}-$(date -u +%Y%m%d-%H%M+0).bb"
BB_File="${BB_Dir}/${BB_File}"

# Query the short and extended test duration, in minutes. Use the values to
# calculate how long we should sleep after starting the SMART tests:

Short_Test_Minutes=$(echo "${SMART_capabilities}" | pcregrep -M 'Short self-test routine.*\n.*recommended polling time:' | sed -e 's:)::' -e 's:(::' | awk '{print $4}' | tr -d '\n')
#printf "Short_Test_Minutes=[%s]\n" ${Short_Test_Minutes}

Conveyance_Test_Minutes=$(echo "${SMART_capabilities}" | pcregrep -M 'Conveyance self-test routine.*\n.*recommended polling time:' | sed -e 's:)::' -e 's:(::' | awk '{print $4}' | tr -d '\n')
#printf "Conveyance_Test_Minutes=[%s]\n" ${Conveyance_Test_Minutes}

Extended_Test_Minutes=$(echo "${SMART_capabilities}" | pcregrep -M 'Extended self-test routine.*\n.*recommended polling time:' | sed -e 's:)::' -e 's:(::' | awk '{print $4}' | tr -d '\n')
#printf "Extended_Test_Minutes=[%s]\n" ${Extended_Test_Minutes}

Short_Test_Sleep="$((Short_Test_Minutes*60))"
Conveyance_Test_Sleep="$((Conveyance_Test_Minutes*60))"
Extended_Test_Sleep="$((Extended_Test_Minutes*60))"

# Selftest polling timeout interval, in hours
Poll_Timeout_Hours="4"

# Calculate the selftest polling timeout interval in seconds
Poll_Timeout="$((Poll_Timeout_Hours*60*60))"

# Polling sleep interval, in seconds:
Poll_Interval="15"

######################################################################
#
# Local functions
#
######################################################################

echo_str() {
  echo "$1" | tee -a "$Log_File"
}

push_header() {
  echo_str "+-----------------------------------------------------------------------------"
}

poll_selftest_complete() {
	l_rv="1"
	l_status="0"
	l_done="0"
	l_pollduration="0"

	# Check SMART results for "The previous self-test routine completed"
	# Return 0 if the test has completed, 1 if we exceed our polling timeout interval

	while [ "${l_done}" -eq "0" ]; do
		smartctl -a "/dev/${driveID}" | grep -i "The previous self-test routine completed" > /dev/null 2<&1
		l_status="${?}"

		if [ "${l_status}" -eq "0" ]; then
			echo_str "SMART self-test complete"
			l_rv="0"
			l_done="1"
		else
			# Check for failure
			smartctl -a "/dev/${driveID}" | grep -i "of the test failed." > /dev/null 2<&1
			l_status="${?}"
			if [ "${l_status}" -eq "0" ]; then
				echo_str "SMART self-test failed"
				l_rv="0"
				l_done="1"
			else
				if [ "${l_pollduration}" -ge "${Poll_Timeout}" ]; then
					echo_str "Timeout polling for SMART self-test status"
					l_done="1"
				else
					sleep "${Poll_Interval}"
					l_pollduration="$((l_pollduration+Poll_Interval))"
				fi
			fi
		fi
	done

  return $l_rv
}

run_short_test() {
	push_header
	echo_str "+ Run SMART short test on drive /dev/${driveID}: $(date)"
	push_header

	if [ "${Dry_Run}" -eq 0 ]; then
		smartctl -d "${driveConnectionType}" -t short "/dev/${driveID}"

		echo_str "Short test started, sleeping ${Short_Test_Sleep} seconds until it finishes"

		sleep "${Short_Test_Sleep}"

		poll_selftest_complete

		smartctl -l selftest "/dev/${driveID}" | tee -a "$Log_File"
	else
		echo_str "Dry run: would start the SMART short test and sleep ${Short_Test_Sleep} seconds until the test finishes"
	fi

	echo_str "Finished SMART short test on drive /dev/${driveID}: $(date)"
}

run_conveyance_test() {
	if [ -z "${Conveyance_Test_Minutes}" ]; then
		push_header
		echo_str "+ SMART conveyance test not supported by /dev/${driveID}; skipping."
		push_header
	eles
		push_header
		echo_str "+ Run SMART conveyance test on drive /dev/${driveID}: $(date)."
		push_header

		if [ "${Dry_Run}" -eq 0 ]; then
			smartctl -d "${driveConnectionType}" -t conveyance "/dev/${driveID}"

			echo_str "Conveyance test started, sleeping ${Conveyance_Test_Sleep} seconds until it finishes."

			sleep "${Conveyance_Test_Sleep}"

			poll_selftest_complete

			smartctl -l selftest "/dev/${driveID}" | tee -a "$Log_File"
		else
			echo_str "Dry run: would start the SMART conveyance test and sleep ${Conveyance_Test_Sleep} seconds until the test finishes."
		fi

		echo_str "Finished SMART conveyance test on drive /dev/${driveID}: $(date)."
	fi
}

run_extended_test() {
	push_header
	echo_str "+ Run SMART extended test on drive /dev/${driveID}: $(date)"
	push_header

	if [ "${Dry_Run}" -eq 0 ]; then
		smartctl -d "${driveConnectionType}" -t long "/dev/${driveID}"

		echo_str "Extended test started, sleeping ${Extended_Test_Sleep} seconds until it finishes"

		sleep "${Extended_Test_Sleep}"

		poll_selftest_complete

		smartctl -l selftest "/dev/${driveID}" | tee -a "$Log_File"
	else
		echo_str "Dry run: would start the SMART extended test and sleep ${Extended_Test_Sleep} seconds until the test finishes"
	fi

	echo_str "Finished SMART extended test on drive /dev/${driveID}: $(date)"
}

run_badblocks_test() {
	push_header
	echo_str "+ Run badblocks test on drive /dev/${driveID}: $(date)"
	push_header

	if [ "${Dry_Run}" -eq "0" ]; then
		#
		# This is the command which erases all data on the disk:
		#
		badblocks -b 4096 -wsv -o "$BB_File" "/dev/${driveID}"
	else
		echo_str "Dry run: would run badblocks -b 4096 -wsv -o ${BB_File} /dev/${driveID}"
	fi

	echo_str "Finished badblocks test on drive /dev/${driveID}: $(date)"
}

######################################################################
#
# Action begins here
#
######################################################################

if [ -e "$Log_File" ]; then
  rm "$Log_File"
fi

tee -a "$Log_File" << EOF
+-----------------------------------------------------------------------------
+ Started burn-in of /dev/${driveID} : $(date)
+-----------------------------------------------------------------------------
Host: $(hostname)
Drive Model: ${Disk_Model}
Serial Number: ${Serial_Number}
Short test duration: ${Short_Test_Minutes} minutes
Short test sleep duration: ${Short_Test_Sleep} seconds
Extended test duration: ${Extended_Test_Minutes} minutes
Extended test sleep duration: ${Extended_Test_Sleep} seconds
Log file: ${Log_File}
Bad blocks file: ${BB_File}
EOF

# Run the test sequence:
run_short_test
run_conveyance_test
run_extended_test
if [ ! "${driveType}" = "ssd" ]; then
	run_badblocks_test
	run_short_test
	run_extended_test
fi

# Emit full device information to log:
tee -a "$Log_File" << EOF
+-----------------------------------------------------------------------------
+ SMART information for drive /dev/${driveID}: $(date)
+-----------------------------------------------------------------------------
$(smartctl -x "/dev/${driveID}")
+-----------------------------------------------------------------------------
+ Finished burn-in of /dev/${driveID} : $(date)
+-----------------------------------------------------------------------------
EOF

# Clean up the log file:

osflavor=$(uname)

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

