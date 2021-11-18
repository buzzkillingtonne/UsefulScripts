#!/bin/bash

#Place this folder in home directory and set as a logon script (such as in KDE's setting application) to prevent keyboard from not working at logon
sudo systemctl start ckb-next-daemon.service 
ckb-next --background
