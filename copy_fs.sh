#!/bin/bash
#

cp ./target/boot/uEnv.txt uEnv.txt

# Kernel modules
cp ./target/src/* ./kmodules

# dts
cp ./target/opt/source/dtb-5.10-ti/src/arm/am335x-boneblack.dts .
