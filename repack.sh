#!/bin/sh
set -e

DIR=$(readlink -f "$(dirname "$0")")

FILE=""
OUTPUT=""
MODE=""

usage()
{
	echo "Usage: $0 [OPTION]..."
	echo "Repackages Microsoft Surface driver MSIs for fwupd"
	echo
	echo "Options:"
	echo "    -h    This help message"
	echo "    -m    The mode the script should operate in"
	echo
	echo "              dir: Create the basic directory structure"
	echo "                   required for fwupd"
	echo
	echo "              cab: Package the firmwares as cabinet files"
	echo "                   for direct flashing with fwupd"
	echo
	echo "              zip: Package the firmwares as cabinet files"
	echo "                   and bundle them to a zip file for deploying"
	echo
	echo "    -f    The file to repack"
	echo "    -o    The directory where to save the output"
	exit
}

while getopts ":hm:f:o:" args; do
	case "$args" in
	m)
		MODE="$OPTARG"
		;;
	f)
		FILE="$OPTARG"
		;;
	o)
		OUTPUT="$OPTARG"
		;;
	h)
		usage
		;;
	*)
		echo "ERROR: Invalid command line option '$args'"
		exit
		;;
	esac
done

if [ ! "$MODE" = "dir" ] && [ ! "$MODE" = "cab" ] && [ ! "$MODE" = "zip" ]; then
	echo "ERROR: Invalid mode specified!"
	exit
fi

if [ "$FILE" = "" ]; then
	echo "ERROR: No filename specified!"
	exit
fi

if [ "$OUTPUT" = "" ]; then
	echo "ERROR: No output directory specified!"
	exit
fi

# Figure out the model name from the MSI file
MODEL=$(basename "$FILE" | cut -d'_' -f1)

echo " ==> Found Model: $MODEL"
echo " ==> Unpacking driver package"

# Unpack the MSI file
TMP=$(mktemp -d)
msiextract -C "$TMP" "$FILE" > /dev/null

# Convert all .inf files to unix format
find "$TMP" \( -iname '*.inf' -or -iname 'ReadMe.txt' \) -exec sh -c 'dos2unix "$0" > /dev/null 2>&1' {} \;

mkdir -p "$OUTPUT/$MODEL"

grep -lR 'Firmware_Install,UEFI' "$TMP" | while IFS= read -r inf; do
	FIRMWARE=$(basename "$(dirname "$inf")")
	FWDIR="$OUTPUT/$MODEL/$FIRMWARE"

	echo " ==> Repacking $FIRMWARE firmware"

	cp -r "$(dirname "$inf")" "$OUTPUT/$MODEL"
	cp "$DIR/template.metainfo.xml" "$FWDIR/$FIRMWARE.metainfo.xml"

	sed -i "s|{MODEL}|$MODEL|g" "$FWDIR"/*.metainfo.xml
	sed -i "s|{FIRMWARE}|$FIRMWARE|g" "$FWDIR"/*.metainfo.xml

	CATEGORY=""
	if echo "$FIRMWARE" | grep -q UEFI; then
		CATEGORY="X-System"
	elif echo "$FIRMWARE" | grep -q ME; then
		CATEGORY="X-ManagementEngine"
	else
		CATEGORY="X-Device"
	fi
	sed -i "s|{CATEGORY}|$CATEGORY|g" "$FWDIR"/*.metainfo.xml

	DEVICE=$(grep 'Firmware_Install, *UEFI' "$inf")
	DEVICE=$(echo "$DEVICE" | cut -d'{' -f2 | cut -d'}' -f1)
	DEVICE=$(echo "$DEVICE" | tr '[:upper:]' '[:lower:]')
	sed -i "s|{DEVICE}|$DEVICE|g" "$FWDIR"/*.metainfo.xml

	MODELFMT=$(grep '^Device' "$TMP"/**/ReadMe.txt | cut -d':' -f2)
	MODELFMT=$(echo "$MODELFMT" | sed 's|^ +||g' | sed 's| +$||g')
	sed -i "s|{MODELFMT}|$MODELFMT|g" "$FWDIR"/*.metainfo.xml

	DRIVERVER=$(grep '^DriverVer' "$inf" | sed 's| +||g')
	DRIVERVER=$(echo "$DRIVERVER" | cut -d'=' -f2)
	MSVER=$(echo "$DRIVERVER" | cut -d',' -f2)
	sed -i "s|{MSVER}|$MSVER|g" "$FWDIR"/*.metainfo.xml

	TIMESTAMP=$(echo "$DRIVERVER" | cut -d',' -f1)
	TIMESTAMP=$(date '+%s' --date "$TIMESTAMP")
	sed -i "s|{TIMESTAMP}|$TIMESTAMP|g" "$FWDIR"/*.metainfo.xml

	UEFIVER=$(grep 'FirmwareVersion' "$inf" | cut -d',' -f5 | sed 's|\r||')
	MAJOR=$(($(("$UEFIVER" >> 24)) & 0xff))
	MINOR=$(($(("$UEFIVER" >> 16)) & 0xff))
	REV=$(("$UEFIVER" & 0xffff))
	UEFIVER="$MAJOR.$MINOR.$REV"
	sed -i "s|{UEFIVER}|$UEFIVER|g" "$FWDIR"/*.metainfo.xml
done

rm -r "$TMP"

if [ "$MODE" = "dir" ]; then
	exit
fi

for dir in "$OUTPUT/$MODEL"/*; do
	PARENT=$(pwd)
	cd "$dir"

	FIRMWARE=$(basename "$dir")
	VERSION=$(grep -Po 'version: "[^"]+"' ./*.metainfo.xml | \
		cut -d'"' -f2 | sed 's|\r||')

	BINFILE=$(basename "$(find . -iname '*.bin' -or -iname '*.cap')")
	CATFILE=$(basename "$(find . -iname '*.cat')")
	INFFILE=$(basename "$(find . -iname '*.inf')")

	TMP=$(mktemp -d)
	cp ./*.metainfo.xml "$TMP/firmware.metainfo.xml"
	cp "$BINFILE" "$TMP/firmware.bin"
	cp "$CATFILE" "$TMP/firmware.cat"
	cp "$INFFILE" "$TMP/firmware.inf"

	cd "$PARENT"

	sed -e "s|$CATFILE|firmware.cat|g" \
		-e "s|$BINFILE|firmware.bin|g" \
		-i "$TMP/firmware.inf"

	gcab -cn "${OUTPUT}/${MODEL}/${MODEL}_${FIRMWARE}_${VERSION}.cab" "${TMP}"/*
	rm -r "${TMP}"
done

if [ "$MODE" = "cab" ]; then
	exit
fi

cd "${OUTPUT}/${MODEL}"
zip "${MODEL}-$(date '+%Y-%m-%d').zip" ./*.cab
