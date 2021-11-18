#!/bin/bash

# Place this folder in home directory and set as a logon script (such as in KDE's setting application) to prevent keyboard from not working at logon
# Disable ckb-next daemon with systemctl disable ckb-next-daemon.service (this script starts it at logon)
sudo systemctl start ckb-next-daemon.service 
ckb-next --background
