#!/bin/bash
set -euo pipefail

FILE=""
OUTPUT="fwupdates"

usage()
{
	echo "Usage: $0 <FILE.msi> [OUTPUTDIR]"
	echo "Repackages Microsoft Surface firmware for fwupd"
	echo
	echo "Options:"
	echo "    -h              This help message"
	echo "    -f <FILE.msi>   The file to repack"
	echo "    -o <OUTPUTDIR]  The directory where to save the output"
	echo "                    (default is '$OUTPUT')"
	exit
}

while getopts ":hf:o:" args; do
	case "$args" in
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

if [ "$FILE" = "" ]; then
    FILE="$1"
    shift
fi

if [ "$1" != "" ]; then
    OUTPUT="$1"
    shift
fi

if [ "$FILE" = "" ]; then
	echo "ERROR: No filename specified!"
	exit 1
fi

if [ "$OUTPUT" = "" ]; then
	echo "ERROR: No output directory specified!"
	exit 1
fi

for c in msiextract gcab dos2unix; do
    if ! command -v $c > /dev/null; then
	echo "ERROR: command '$c' not found, please install the corresponding package"
	exit 1
done


repackinf()
{
	# Parse parameters
	INF="${1}"
	OUT="${2}"

	# What is the name of the firmware?
	DIR="$(dirname "${INF}")"
	FIRMWARE="$(basename "${DIR}")"

	# Create a working directory
	TEMP="$(mktemp -p . -d)"

	# Copy over files
	BINFILE="$(find "${DIR}" -iname '*.bin' -or -iname '*.cap' | head -n1)"
	CATFILE="$(find "${DIR}" -iname '*.cat' | head -n1)"
	INFFILE="$(find "${DIR}" -iname '*.inf')"

	if [ "$BINFILE" = "" ]; then
		echo "==> Skipping ${INF}"
		return 0
	fi

	cp "${BINFILE}" "${TEMP}/firmware.bin"
	cp "${CATFILE}" "${TEMP}/firmware.cat"
	cp "${INFFILE}" "${TEMP}/firmware.inf"

	# Update paths in the .inf file
	sed -i "s|$(basename "${BINFILE}")|firmware.bin|g" "${TEMP}/firmware.inf"
	sed -i "s|$(basename "${CATFILE}")|firmware.cat|g" "${TEMP}/firmware.inf"

	# Create metainfo file
	cp template.metainfo.xml "${TEMP}/firmware.metainfo.xml"

	# Update the device GUID
	DEVICE="$(grep -m1 'Firmware_Install, *UEFI' "${TEMP}/firmware.inf")"
	DEVICE="$(echo "${DEVICE}" | cut -d'{' -f2 | cut -d'}' -f1)"
	DEVICE="$(echo "${DEVICE}" | tr '[:upper:]' '[:lower:]')"
	sed -i "s|{DEVICE}|${DEVICE}|g" "${TEMP}/firmware.metainfo.xml"

	# Update firmware type
	CATEGORY="X-Device"
	if echo "${FIRMWARE}" | grep -q UEFI; then
		CATEGORY="X-System"
	elif echo "${FIRMWARE}" | grep -q ME; then
		CATEGORY="X-ManagementEngine"
	fi
	sed -i "s|{CATEGORY}|${CATEGORY}|g" "${TEMP}/firmware.metainfo.xml"

	# Update firmware version
	VERSION="$(grep 'FirmwareVersion' "${TEMP}/firmware.inf" | cut -d',' -f5 | sed 's|\r||')"
	MAJOR="$(( (VERSION >> 24) & 0xff ))"
	MINOR="$(( (VERSION >> 16) & 0xff ))"
	REV="$(( VERSION & 0xffff ))"
	VERSION="${MAJOR}.${MINOR}.${REV}"
	sed -i "s|{VERSION}|${VERSION}|g" "${TEMP}/firmware.metainfo.xml"

	# Update firmware timestamp
	TIMESTAMP="$(grep '^DriverVer' "${TEMP}/firmware.inf" | sed -E 's| +||g')"
	TIMESTAMP="$(echo "${TIMESTAMP}" | cut -d'=' -f2 | cut -d',' -f1)"
	TIMESTAMP="$(date '+%s' --date "${TIMESTAMP}")"
	sed -i "s|{TIMESTAMP}|${TIMESTAMP}|g" "${TEMP}/firmware.metainfo.xml"

	# Create a cab file of the firmware
	gcab -cn "${OUT}/${FIRMWARE}_${VERSION}_${DEVICE}.cab" "${TEMP}"/*
	rm -r "${TEMP}"
}

repackdir()
{
	DIR="${1}"
	OUT="${2}"

	# Convert all .inf files to unix format
	find "${DIR}" -iname '*.inf' -exec sh -c 'dos2unix "$0" > /dev/null 2>&1' {} \;

	# Repack all UEFI capsule updates found in the directory
	grep -lR 'Firmware_Install,UEFI' "${DIR}" | while IFS= read -r INF; do
		echo "==> Repacking ${INF}"

		repackinf "${INF}" "${OUT}"
	done
}

repackmsi()
{
	MSI="${1}"
	OUT="${2}"

	echo "==> Extracting ${MSI}"

	# Extract the MSI
	TEMP="$(mktemp -p . -d)"
	msiextract -C "${TEMP}" "${MSI}" > /dev/null

	# Repack all .inf files in the extracted MSI
	repackdir "${TEMP}" "${OUT}"

	# Clean up
	rm -r "${TEMP}"
}

repackcab()
{
	CAB="${1}"
	OUT="${2}"

	echo "==> Extracting ${CAB}"

	# Extract the CAB
	TEMP="$(mktemp -p . -d)"
	gcab -C "${TEMP}" -x "${CAB}" > /dev/null

	# Convert all .inf files to unix format
	find "${TEMP}" -iname '*.inf' -exec sh -c 'dos2unix "$0" > /dev/null 2>&1' {} \;

	# Repack all UEF capsule updates found in the CAB
	grep -lR 'Firmware_Install,UEFI' "${TEMP}" | while IFS= read -r INF; do
		echo "==> Repacking ${INF}"

		repackinf "${INF}" "${OUT}"
	done

	# Clean up
	rm -r "${TEMP}"
}

mkdir -p "${OUTPUT}"

if echo "${FILE}" | grep -Eiq "\.msi$"; then
	repackmsi "${FILE}" "${OUTPUT}"
elif echo "${FILE}" | grep -Eiq "\.cab$"; then
	repackcab "${FILE}" "${OUTPUT}"
elif echo "${FILE}" | grep -Eiq "\.inf$"; then
	repackinf "${FILE}" "${OUTPUT}"
elif [ -d "${FILE}" ]; then
	repackdir "${FILE}" "${OUTPUT}"
else
	echo "==> Invalid file type!"
	exit 1
fi
