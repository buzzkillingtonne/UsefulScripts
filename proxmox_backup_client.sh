#!/bin/bash

### Depedencies ########################################
# proxmox-backup-client                                #
# postfix                                              #
# libsasl2-modules (on debian)                         #
# jq (to parse the json output of snapshots)           #
#                                                      #
# PBS_PASSWORD must be exported in:                    #
#   ~/.bashrc (to be run by user)                      #
#   ~/.bash_profile (to be run by cron with "bash -l") #
# In this script I've exported it manually and cleared #
# the variable at the end                              #
########################################################

### Settings ######################
EMAIL="address@example.com"
_pbs_ip_address="X.X.X.X"
_pbs_user="username@pbs!username-api"
_pbs_user_upid=username@pbs!username-api
_pbs_datastore=""
_pbs_client=$(hostname)
_pbs_backup_dir=""
export PBS_PASSWORD=<GET THIS FROM YOUR PBS SERVER>
export PBS_FINGERPRINT=<GET THIS FROM YOUR PBS SERVER>
###################################

# Check; not connected to a metered network
# (See https://developer.gnome.org/NetworkManager/stable/nm-dbus-types.html#NMMetered)

_metered_value=$(busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Metered)

function run_backup {
# Run the backup if the last backup is more than 24H old (86400 seconds)
if [[ $_seconds_elapsed_since_last_backup -ge 86300 ]]; then

	printf -- "- Starting the PBS backup" | systemd-cat
	proxmox-backup-client backup $_pbs_backup_dir.pxar:/$_pbs_backup_dir --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore
	printf -- "- PBS backup completed" | systemd-cat
	printf -- "- $0 completed at `date`" | systemd-cat
	printf -- "- Gathering information for email" | systemd-cat
	_backup_upid=$(proxmox-backup-client task list --all --limit 2 --output-format json --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore | jq -r '[ .[]."upid" ]' | grep backup | tr -d '"''  ' | tr -s '\\' '\\'  | awk -F 'x2ddesktop:' '{print $1"x2ddesktop:"}')
	_last_backup_job_status=$(proxmox-backup-client task log $_backup_upid$_pbs_user_upid: --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore)
	_job_status=$(proxmox-backup-client task log $_backup_upid$_pbs_user_upid: --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore | tail -1)
	printf -- "- Clearing enviroment variables" | systemd-cat
	export PBS_PASSWORD=
	export PBS_FINGERPRINT=
	printf -- "- Sending email" | systemd-cat
	mail -s "Proxmox Backup Client $_pbs_client status $_job_status"  $EMAIL <<< "$_last_backup_job_status"
	printf -- "- $0 completed at `date`" | systemd-cat
else
	printf -- "- $_seconds_elapsed_since_last_backup seconds elapsed since last backup, must be greater than 86400" | systemd-cat
fi
}

if [[ "$_metered_value" == "u 4" ]] || [[ "$_metered_value" == "u 2" ]]; then
	printf -- "- The bandwidth on this network is probably not metered" | systemd-cat

# Check that the PBS server is pingable
	ping $_pbs_ip_address -c 1 > /dev/null 2>&1

	if [[ $? == 0 ]]; then
		printf -- "- The Proxmox Backup Server is reachable" | systemd-cat
		_backups=($(proxmox-backup-client snapshots --output-format json-pretty --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore  | jq -r --arg host $_pbs_client '.[] | select(."backup-id" == $host) | ."backup-time"'))
		_sorted_backups=($(for i in "${_backups[@]}"; do echo $i; done | sort -n))
		_epoch_last_backup=${_sorted_backups[-1]}
		
# Verify there there was a previous backup, and if so when
		if [[ ! -z $_epoch_last_backup ]]; then
			_seconds_elapsed_since_last_backup=$(($(date +%s)-$_epoch_last_backup))
			printf -- "- The last backup was received on $(date -d @$_epoch_last_backup) ($_seconds_elapsed_since_last_backup seconds ago)" | systemd-cat
			run_backup
		else
			_epoch_last_backup=99999999
			_seconds_elapsed_since_last_backup=$(($(date +%s)-$_epoch_last_backup))
			printf -- "- There was no previous backup" | systemd-cat
			run_backup
		fi
	else
		printf -- "- The Proxmox Backup Server is NOT reachable" | systemd-cat
	fi
else
	printf -- "- The bandwidth on this network is probably metered" | systemd-cat
fi
