#!/bin/bash
# Thanks to https://www.reddit.com/r/jellyfin/comments/cig9kh/nvidia_quadro_p400_passthrough_on_proxmox/
# Create this script in a directory such as /root/boot-scripts/ and add to a cronjob in /etc/cron.d/ to run @reboot
# Ensure in /etc/modules that the VFIO kernel modules are listed before the nvidia modules, ideally the nvidia modules should be in their own file unter /etc/module-load.d/nvidia.conf.
# This will ensure that the selected PCI GPU in this script will get the vfio drivers, and the other PCI GPU of the same model will get the nvidia drivers applied

/sbin/modprobe nvidia

# find the PCI address of the device you want to have the vfio drivers applied to by using lspci
PCIaddress='04:00'

if [ "$?" -eq 0 ]; then
    # Count the number of NVIDIA controllers found.
    NVDEVS=$(lspci | grep -i "$PCIaddress")
    N3D=$(echo "$NVDEVS" | grep "3D controller" | wc -l)
    NVGA=$(echo "$NVDEVS" | grep "VGA compatible controller" | wc -l)
    N=$(expr $N3D + $NVGA - 1)
    for i in $(seq 0 $N); do
        mknod -m 666 /dev/nvidia$i c 195 $i
    done
    mknod -m 666 /dev/nvidiactl c 195 255
else
    exit 1
fi

/sbin/modprobe nvidia-uvm

if [ "$?" -eq 0 ]; then
     # Find out the major device number used by the nvidia-uvm driver
     D=$(grep nvidia-uvm /proc/devices | awk '{print $1}')
     mknod -m 666 /dev/nvidia-uvm c $D 0
else
    exit 1
fi

/usr/bin/nvidia-modprobe -u -c 0
