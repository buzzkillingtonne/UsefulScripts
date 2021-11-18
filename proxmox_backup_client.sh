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
_pbs_user_upid=andrew@pbs!andrew-api
_pbs_datastore=""
_pbs_client=$(hostname)
_pbs_backup_dir=""
export PBS_PASSWORD=<GET THIS FROM YOUR PBS SERVER>
export PBS_FINGERPRINT=<GET THIS FROM YOUR PBS SERVER>
###################################


# Check; not connected to a metered network
# (See https://developer.gnome.org/NetworkManager/stable/nm-dbus-types.html#NMMetered)

_metered_value=$(busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Metered)

#set -x

if [[ "$_metered_value" == "u 4" ]] || [[ "$_metered_value" == "u 2" ]]; then
        printf "- The bandwidth on this network is probably not metered" | systemd-cat

# Check that the PBS server is pingable
        ping $_pbs_ip_address -c 1 > /dev/null 2>&1

        if [[ $? == 0 ]]; then
                printf "- The Proxmox Backup Server is reachable" | systemd-cat
                _epoch_last_backup=$(proxmox-backup-client snapshots --output-format json --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore | jq '[ .[]."backup-time" ] | max')
                _seconds_elapsed_since_last_backup=$(($(date +%s)-$_epoch_last_backup))
                printf "- The last backup was received on "$(date -d @$_epoch_last_backup)" ("$_seconds_elapsed_since_last_backup" seconds ago)" | systemd-cat

# Run the backup if the last one is more than 24H old (86400 seconds)
                if [[ $_seconds_elapsed_since_last_backup -ge 86300 ]]; then
                        printf "- Starting the PBS backup" | systemd-cat
                        proxmox-backup-client backup $_pbs_backup_dir.pxar:/$_pbs_backup_dir --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore
                        printf "- PBS backup completed" | systemd-cat
                        printf "$0 completed at `date`" | systemd-cat
                        printf "- Gathering information for email" | systemd-cat
                        _backup_upid=$(proxmox-backup-client task list --all --limit 2 --output-format json --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore | jq '[ .[]."upid"|tostring ]' | grep backup | cut -c4- | rev | cut -c24- | rev | tr -s '\\' '\\')
                        _last_backup_job_status=$(proxmox-backup-client task log $_backup_upid$_pbs_user_upid: --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore)
                        _job_status=$(proxmox-backup-client task log $_backup_upid$_pbs_user_upid: --repository $_pbs_user@$_pbs_ip_address:$_pbs_datastore | tail -1)
                        printf "- Clearing enviroment variables" | systemd-cat
                        export PBS_PASSWORD=
                        export PBS_FINGERPRINT=
                        printf "- Sending email" | systemd-cat
                        mail -s "Proxmox Backup Client $_pbs_client status $_job_status"  $EMAIL <<< "$_last_backup_job_status"
                        printf "$0 completed at `date`" | systemd-cat
                fi

        fi

fi
#set +x
