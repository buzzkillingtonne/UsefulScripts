#!/bin/bash

## I would like to thank Turnicus on the Proxmox forums for creating the basis of this script:
## https://forum.proxmox.com/threads/proxmox-backup-client-bash-script-for-automated-backups-of-laptop.78358/

### Depedencies #########################################
# proxmox-backup-client					#
# postfix (for email alerts daemon must be enabled)	#
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
## I have designed this script to run once per day and retry when there are failures. This allows the script to also be exectuted manually.
#

### Settings ######################
EMAIL='address@example.com'
_pbs_ip_address='X.X.X.X'
_pbs_user='username@pbs!username-api'
_pbs_datastore=''
_pbs_client=$(hostname)
# _pbs_backup_dir backs up root by default. It's currently set to backup root, it will not automatically backup additional disks mounted on root. This must be done with the --include-dev flag.
_pxar_file_name='root'
_pbs_backup_dir1='/'
# below is an example of backing up root with /home on a different drive or partition. --include-dev can be specified more than once and allows you to backup multiple mount locations.
#_pbs_backup_dir2='--include-dev /home'
_pbs_backup_dir2=''
export PBS_PASSWORD=<GET THIS FROM YOUR PBS SERVER>
export PBS_FINGERPRINT=<GET THIS FROM YOUR PBS SERVER>
###################################

# Check; not connected to a metered network
# (See https://developer.gnome.org/NetworkManager/stable/nm-dbus-types.html#NMMetered)

_metered_value=$(busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Metered)

function run_backup {

printf -- "- Starting the PBS backup" | systemd-cat -t 'proxmox backup client'
if proxmox-backup-client backup $_pxar_file_name.pxar:$_pbs_backup_dir1 $_pbs_backup_dir2 --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore; then
	printf -- "- PBS backup completed" | systemd-cat -t 'proxmox backup client'
	printf -- "- $0 completed at $(date)" | systemd-cat -t 'proxmox backup client'
	printf -- "- Gathering information for email" | systemd-cat -t 'proxmox backup client'
# This must be the the for of 'UPID:yourpbdserverhostname:0002A09D:0AEE0BA0:0000049B:61BD33FA:backup:yourbackuprepositoryname\x3ahost-yourpbsusername\x2ddesktop:' without quotes
# It is important that backup jobs for different computers use different pbs user names and api's, this script finds the backup to report on based on the last backup taken with that username.
	_backup_upid=$(proxmox-backup-client task list --all --limit 2 --output-format json --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore | jq -r '[ .[]."upid" ]' | grep backup | tr -d '"''  ' | tr -s '\\' '\\'  | awk -F 'x2ddesktop:' '{print $1"x2ddesktop:"}')
	_last_backup_job_status=$(proxmox-backup-client task log "$_backup_upid"$_pbs_user: --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore 2>&1 | grep -v 'successfully added chunk\|dynamic_append 128 chunks\|PUT /dynamic_index\|upload_chunk done:\|POST /dynamic_chunk\|dynamic_append\|GET\|POST')
	_job_status=$(proxmox-backup-client task log "$_backup_upid"$_pbs_user: --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore 2>&1 | tail -1)
		
	printf -- "- Clearing enviroment variables" | systemd-cat -t 'proxmox backup client'
	unset PBS_PASSWORD
	unset PBS_FINGERPRINT
	printf -- "- Sending email" | systemd-cat -t 'proxmox backup client'
	mail -s "Proxmox Backup Client $_pbs_client status $_job_status"  $EMAIL <<< "$_last_backup_job_status"
	printf -- "- $0 completed at $(date)" | systemd-cat -t 'proxmox backup client'
else
	sleep 300
	retry=$(($retry+1))
	# Retry running the backup up to 2 more times before failing and sending an email
	while [ $retry -lt 3 ]; do
		run_backup
	done
fi		

}


function backup_failure_notification {

if [[ $retry -ge 3 ]]; then
	printf -- "- proxmox-backup-client failed with exit status $?" | systemd-cat -t 'proxmox backup client'
	mail -s "Proxmox Backup Client $_pbs_client status TASK FAILED after three retries"  $EMAIL <<< "Backup job failed, check the task log manually for more information"
fi
}

# set the retry counter
retry=0

if [[ "$_metered_value" == "u 4" ]] || [[ "$_metered_value" == "u 2" ]]; then
	printf -- "- The bandwidth on this network is probably not metered" | systemd-cat -t 'proxmox backup client'

# Check that the PBS server is pingable
	if ping $_pbs_ip_address -c 1 > /dev/null 2>&1; then
		printf -- "- The Proxmox Backup Server is reachable" | systemd-cat -t 'proxmox backup client'
		_backups=($(proxmox-backup-client snapshots --output-format json-pretty --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore | jq -r --arg host $(hostname) '.[] | select(."backup-id" == $host) | ."backup-time"'))
		_sorted_backups=($(for i in "${_backups[@]}"; do echo "$i"; done | sort -n))
		_epoch_last_backup=${_sorted_backups[-1]}

# Verify there there was a previous backup, and if so when
		if [[ -n $_epoch_last_backup ]]; then
			_seconds_elapsed_since_last_backup=$(($(date +%s)-_epoch_last_backup))
			printf -- "- The last backup was received on $(date -d @"$_epoch_last_backup") ($_seconds_elapsed_since_last_backup seconds ago)" | systemd-cat -t 'proxmox backup client'
			run_backup
			backup_failure_notification
		else
			_epoch_last_backup=99999999
			_seconds_elapsed_since_last_backup=$(($(date +%s)-_epoch_last_backup))
			printf -- "- There probably was no previous backup - taking a fresh backup now" | systemd-cat -t 'proxmox backup client'
			run_backup
			backup_failure_notification
		fi

	else
    		printf -- "- The Proxmox Backup Server is NOT reachable, exiting" | systemd-cat -t 'proxmox backup client'
	fi
else
	printf -- "- The bandwidth on this network is probably metered, exiting" | systemd-cat -t 'proxmox backup client'
fi
