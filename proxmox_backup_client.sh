#!/bin/bash

## I would like to thank Turnicus on the Proxmox forums for creating the basis of this script:
## https://forum.proxmox.com/threads/proxmox-backup-client-bash-script-for-automated-backups-of-laptop.78358/

### Depedencies #########################################
# proxmox-backup-client					#
# postfix (for email alerts)				#
# libsasl2-modules (on debian, needed for sasl hash)	#
# jq (to parse the json output of snapshots and email	#
# info)							#
# awk (parsing information for email)			#
#							#
# PBS_PASSWORD must be exported in:			#
#   ~/.bashrc (to be run by user)			#
#   ~/.bash_profile (to be run by cron with "bash -l")	#
# In this script I've exported it manually and cleared	#
# the variable at the end, i found this to be easier	#
# and more reliable when running in a cron job		#
#########################################################

#
## I have designed this script to run every minute in a cron job, this is not the best, but it works fine. It can however get spammy when there are failures.
#

### Settings ######################
EMAIL='address@example.com'
_pbs_ip_address='X.X.X.X'
_pbs_user='username@pbs!username-api'
_pbs_datastore=''
_pbs_client=$(hostname)
# _pbs_backup_dir backs up root by default, change to the directory desired eg. home
# (!IMPORTANT! you cannot put the preceeding / in the variable, it will fail.)
_pbs_backup_dir=''
export PBS_PASSWORD=<GET THIS FROM YOUR PBS SERVER>
export PBS_FINGERPRINT=<GET THIS FROM YOUR PBS SERVER>
###################################

# Check; not connected to a metered network
# (See https://developer.gnome.org/NetworkManager/stable/nm-dbus-types.html#NMMetered)

_metered_value=$(busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Metered)

function run_backup {
# Run the backup if the last backup is more than 24H old (86400 seconds)
if [[ $_seconds_elapsed_since_last_backup -ge 86400 ]]; then

	printf -- "- Starting the PBS backup" | systemd-cat
	if proxmox-backup-client backup $_pbs_backup_dir.pxar:/$_pbs_backup_dir --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore; then
		printf -- "- PBS backup completed" | systemd-cat
		printf -- "- $0 completed at $(date)" | systemd-cat
		printf -- "- Gathering information for email" | systemd-cat
# This must be the the for of 'UPID:yourpbdserverhostname:0002A09D:0AEE0BA0:0000049B:61BD33FA:backup:yourbackuprepositoryname\x3ahost-yourpbsusername\x2ddesktop:' without quotes
# It is important that backup jobs for different computers use different pbs user names and api's, this script finds the backup to report on based on the last backup taken with that username.
		_backup_upid=$(proxmox-backup-client task list --all --limit 2 --output-format json --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore | jq -r '[ .[]."upid" ]' | grep backup | tr -d '"''  ' | tr -s '\\' '\\'  | awk -F 'x2ddesktop:' '{print $1"x2ddesktop:"}')
		_last_backup_job_status=$(proxmox-backup-client task log "$_backup_upid"$_pbs_user: --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore 2>&1 | grep -v 'successfully added chunk\|dynamic_append 128 chunks\|PUT /dynamic_index\|upload_chunk done:\|POST /dynamic_chunk\|dynamic_append\|GET\|POST')
		_job_status=$(proxmox-backup-client task log "$_backup_upid"$_pbs_user: --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore 2>&1 | tail -1)
		
		printf -- "- Clearing enviroment variables" | systemd-cat
		unset PBS_PASSWORD
		unset PBS_FINGERPRINT
		printf -- "- Sending email" | systemd-cat
		mail -s "Proxmox Backup Client $_pbs_client status $_job_status"  $EMAIL <<< "$_last_backup_job_status"
		printf -- "- $0 completed at $(date)" | systemd-cat
	else
		printf -- "- proxmox-backup-client failed with exit status $?"
		mail -s "Proxmox Backup Client $_pbs_client status TASK FAILED"  $EMAIL <<< "Backup job failed, check the task log manually for more information"
	fi
		
else
	printf -- "- $_seconds_elapsed_since_last_backup seconds elapsed since last backup, must be greater than 86400, exiting" | systemd-cat
fi
}


if [[ "$_metered_value" == "u 4" ]] || [[ "$_metered_value" == "u 2" ]]; then
	printf -- "- The bandwidth on this network is probably not metered" | systemd-cat

# Check that the PBS server is pingable
	if ping $_pbs_ip_address -c 1 > /dev/null 2>&1; then
		printf -- "- The Proxmox Backup Server is reachable" | systemd-cat
		_backups=($(proxmox-backup-client snapshots --output-format json-pretty --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore | jq -r --arg host $(hostname) '.[] | select(."backup-id" == $host) | ."backup-time"'))
		_sorted_backups=($(for i in "${_backups[@]}"; do echo "$i"; done | sort -n))
		_epoch_last_backup=${_sorted_backups[-1]}

# Verify there there was a previous backup, and if so when
		if [[ -n $_epoch_last_backup ]]; then
			_seconds_elapsed_since_last_backup=$(($(date +%s)-_epoch_last_backup))
			printf -- "- The last backup was received on $(date -d @"$_epoch_last_backup") ($_seconds_elapsed_since_last_backup seconds ago)" | systemd-cat
			run_backup
		else
			_epoch_last_backup=99999999
			_seconds_elapsed_since_last_backup=$(($(date +%s)-_epoch_last_backup))
			printf -- "- There probably was no previous backup - taking a fresh backup now" | systemd-cat
			run_backup
		fi

	else
    		printf -- "- The Proxmox Backup Server is NOT reachable, exiting" | systemd-cat
	fi
else
	printf -- "- The bandwidth on this network is probably metered, exiting" | systemd-cat
fi
