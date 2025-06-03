#!/bin/bash

#!/bin/bash

WGET=https://files.beagle.cc/file/beagleboard-public-2021/images/am335x-eMMC-flasher-debian-12.2-iot-armhf-2023-10-07-4gb.img.xz
DEVICE=/dev/sdb

_FILENAME="${WGET##*/}"         # Extract filename from URL
_IMG="${_FILENAME%.xz}"         # Remove .xz extension to get the .img name

wget -nc "$WGET"
unxz "$_FILENAME"
echo "dd ..."
sudo dd if="$_IMG" of="$DEVICE" bs=4M conv=sync status=progress




