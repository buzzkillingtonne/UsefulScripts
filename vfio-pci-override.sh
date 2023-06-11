#!/bin/sh
# Ensure in /etc/modules that the VFIO kernel modules are listed before the nvidia modules, ideally the nvidia modules should be in their own file unter /etc/module-load.d/nvidia.conf.
# This will ensure that the selected PCI GPU in this script will get the vfio drivers, and the other PCI GPU of the same model will get the nvidia drivers applied

DEVS="0000:42:00.0"

if [ ! -z "$(ls -A /sys/class/iommu)" ]; then
    for DEV in $DEVS; do
        for IOMMUDEV in $(ls /sys/bus/pci/devices/$DEV/iommu_group/devices) ; do
            echo "vfio-pci" > /sys/bus/pci/devices/$IOMMUDEV/driver_override
        done
    done
fi

modprobe -i vfio-pci
