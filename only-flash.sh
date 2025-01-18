#! /bin/bash -x

SCRIPT_NAME=${0##*/}
readonly SCRIPT_VERSION="0.1"
#### global variables ####
readonly ABSOLUTE_FILENAME=`readlink -e "$0"`
readonly ABSOLUTE_DIRECTORY=`dirname ${ABSOLUTE_FILENAME}`
readonly SCRIPT_POINT=${ABSOLUTE_DIRECTORY}

#
# environment variables affecting the build:
#
# keep_toolchain=y	-- don't rebuild the toolchain, but rebuild everything else
# keep_rootfs=y		-- don't reconfigure or rebuild rootfs from scratch. Would still apply overlay changes
# keep_buildroot=y	-- don't redownload the buildroot, only git pull any updates into it
# keep_bootloader=y	-- don't redownload the bootloader, only rebuild it
# keep_etc=y		-- don't overwrite the /etc partition
#

#### DBG #####
keep_toolchain=y
keep_rootfs=y	
keep_buildroot=y
keep_bootloader=y

SET_BAUDRATE='-b 2000000'

CTNG_VER=xtensa-fdpic
CTNG_CONFIG=xtensa-esp32s3-linux-uclibcfdpic
BUILDROOT_VER=xtensa-2024.08-fdpic-pressure_sniffer
ESP_HOSTED_VER=ipc-5.1.1-pressure_sniffer
ESP_HOSTED_CONFIG=sdkconfig.defaults.esp32s3

function die()
{
	echo "$1"
	exit 1
}

while : ; do
	case "$1" in
		-c)
			conf="$2"
			. "$conf"
			shift 2
			named_config=1
			;;
		*)
			break
			;;
	esac
done

if [ -z "$named_config" ] ; then
	[ -f default.conf ] || { echo "Making pressure_sniffer the default configuration" ; ln -s pressure_sniffer.conf default.conf ; }
	. default.conf || die "No config selected and default.conf couldn't be loaded"
fi

[ -n "$BUILDROOT_CONFIG" ] || die "BUILDROOT_CONFIG is missing"
[ -n "$ESP_HOSTED_CONFIG" ] || die "ESP_HOSTED_CONFIG is missing"

#
# bootloader
#
[ -d esp-hosted ] || git clone https://github.com/rfilipovich/esp-hosted.git -b $ESP_HOSTED_VER
pushd esp-hosted/esp_hosted_ng/esp/esp_driver
cmake .
cd esp-idf
. export.sh
cd ../network_adapter
idf.py set-target esp32s3
cp $ESP_HOSTED_CONFIG sdkconfig || die "Could not apply IDF config $ESP_HOSTED_CONFIG"
idf.py build
read -p 'ready to flash... press enter'
while ! idf.py $SET_BAUDRATE flash ; do
	read -p 'failure... press enter to try again'
done
popd

#
# flash
#
parttool.py $SET_BAUDRATE write_partition --partition-name linux  --input ${SCRIPT_POINT}/build/build-buildroot-$BUILDROOT_CONFIG/images/xipImage
parttool.py $SET_BAUDRATE write_partition --partition-name rootfs --input ${SCRIPT_POINT}/build/build-buildroot-$BUILDROOT_CONFIG/images/rootfs.cramfs
if [ -z "$keep_etc" ] ; then
	read -p 'ready to flash /etc... press enter'
	parttool.py $SET_BAUDRATE write_partition --partition-name etc --input ${SCRIPT_POINT}/build/build-buildroot-$BUILDROOT_CONFIG/images/etc.jffs2
fi
