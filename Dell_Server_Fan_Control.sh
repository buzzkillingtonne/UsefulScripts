#!/bin/bash
#
#
# ----------------------------------------------------------------------------------
# Script for checking the temperature reported by the ambient temperature sensor,
# and if deemed too high send the raw IPMI command to enable dynamic fan control.
# If deemed low enough  while RPM is high send the raw IPMI command to re-enable 
# manual fan control.
#
#
# Requires:
# ipmitool – apt install ipmitool
# postfix and libsasl2-modules - required for email alerts - apt install postfix libsasl2-modules - this will need to be configured in order to send email alerts
# systemd for logging
# ----------------------------------------------------------------------------------

# Credential File location (This file should have 600 permissions and be stored in a location only root can access)
FILE="/root/.IPMIcred"

# Email Address and hostname for alerts.
EMAIL='address@example.com'
HOST=$(hostname)

# IPMI SETTINGS:
# DEFAULT IPMI IP: 192.168.0.120
IPMIHOST=x.x.x.x
IPMIUSER=root
IPMIPW=$(cat "$FILE")
IPMIEK=0000000000000000000000000000000000000000

# SETFAN is hex for the fan speed to be manually set. 15 is close to default. 09 is about 1920 RPM which is fairly silent.
SETFAN=09
FANTHRESHOLD=2000

# TEMPERATURE
# Change this to the temperature in celcius you are comfortable with.
# If the temperature goes above the set THRESHOLD it will send raw IPMI command to enable dynamic fan control.
# If the temperature goes below the set THRESHOLD it will check fan speed and send raw IPMI command to enable manual fan control at 1920rpm.

# CPU Threshold in °C (Used for Dell R720 typically)
#THRESHOLD=60

# Ambient Threshold in °C (Used for Dell R710 typically)
THRESHOLD=30

# Get the average temp of both CPU's (not all cores combined, only the packages)
# Comment these lines out if using exhaust or ambient temp and uncomment CPU Temp
#
#TEMParray=( $(sensors -u | grep -A 1 -i "Package id" | grep -i "_input:" | grep -Po '\d{2}.\d{1}' | cut -b -2) )
#CPUPACKAGES=$(echo "${#TEMParray[@]}")
#TEMPTOTAL=$(sensors -u | grep -A 1 -i "Package id" | grep -i "_input:" | grep -Po '\d{2}.\d{1}' | cut -b -2 | paste -sd+ | bc)
#TEMP=$(expr $TEMPTOTAL / $CPUPACKAGES)

# This variable sends a IPMI command to get the temperature, and outputs it as two digits.
# Dell R710 ambient temp
TEMP=$(ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y $IPMIEK sdr type temperature | grep "Ambient" | grep -Po '\d{2}' | tail -1)
#
# Dell R720 Exhaust Temp
#TEMP=$(ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y $IPMIEK sdr type temperature | grep "Exhaust Temp" | grep -Po '\d{2}' | tail -1)


# This variable sends a IPMI command to get the fan speed, and outputs it as four digits. R710 and R720 use different naming conventions.
# Dell R710 Fan Name
FANSPEED=$(ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y $IPMIEK sdr type Fan | grep 'FAN 1 RPM' | grep -Po '\d{4}' | tail -1)
#
# Dell R720 Fan Name
#FANSPEED=$(ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y $IPMIEK sdr type Fan | grep 'Fan1' | grep -Po '\d{4}' | tail -1)



if [[ $TEMP -gt $THRESHOLD ]]; then

    if [[ $FANSPEED -lt $FANTHRESHOLD ]]; then
    # Log to journalctl
        printf "Warning: Temperature is too high! Activating dynamic fan control! ($TEMP °C)" | systemd-cat -t R720-IPMI-TEMP
    # Set fan to firmware controlled
        ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y $IPMIEK raw 0x30 0x30 0x01 0x01
    # Email revevant information
        mail -s "Temperature threshold reached on $HOST" $EMAIL <<< "Temperature threshold ($THRESHOLD °C) reached on $HOST, current temperature is ($TEMP °C). Fans set to BIOS control."
    fi


elif [[ $TEMP -lt $THRESHOLD ]]; then
    
    if [[ $FANSPEED -gt $FANTHRESHOLD ]]; then
    # Log to journalctl
        printf "Temperature is OK ($TEMP °C) Activating manual fan speeds!" | systemd-cat -t R720-IPMI-TEMP
    #Set the fans to be controlled manually
        ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y $IPMIEK raw 0x30 0x30 0x01 0x00
    # Set the fan speed manually
        ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW -y $IPMIEK raw 0x30 0x30 0x02 0xff 0x$SETFAN
    # Email relevant information
        mail -s "Temperature normalized on $HOST" $EMAIL <<< "Temperature has gone back to normal on $HOST, Threshold is ($THRESHOLD °C) current temperature is ($TEMP °C). Fans set manually."
    fi

fi

