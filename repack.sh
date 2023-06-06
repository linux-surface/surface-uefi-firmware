#!/bin/bash
set -e

FILE=""
OUTPUT=""

usage()
{
	echo "Usage: $0 [OPTION]..."
	echo "Repackages Microsoft Surface firmware for fwupd"
	echo
	echo "Options:"
	echo "    -h    This help message"
	echo "    -f    The file to repack"
	echo "    -o    The directory where to save the output"
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
	echo "ERROR: No filename specified!"
	exit
fi

if [ "$OUTPUT" = "" ]; then
	echo "ERROR: No output directory specified!"
	exit
fi

if ! command -v "msiextract" > /dev/null; then
	echo "ERROR: command 'msiextract' not found, please install the corresponding package"
	exit
fi

if ! command -v "gcab" > /dev/null; then
	echo "ERROR: command 'gcab' not found, please install the corresponding package"
	exit
fi

if ! command -v "dos2unix" > /dev/null; then
	echo "ERROR: command 'dos2unix' not found, please install the corresponding package"
	exit
fi

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

repackmsi()
{
	MSI="${1}"
	OUT="${2}"

	echo "==> Extracting ${MSI}"

	# Extract the MSI
	TEMP="$(mktemp -p . -d)"
	msiextract -C "${TEMP}" "${MSI}" > /dev/null

	# Convert all .inf files to unix format
	find "${TEMP}" -iname '*.inf' -exec sh -c 'dos2unix "$0" > /dev/null 2>&1' {} \;

	# Repack all UEF capsule updates found in the MSI
	grep -lR 'Firmware_Install,UEFI' "${TEMP}" | while IFS= read -r INF; do
		echo "==> Repacking ${INF}"

		repackinf "${INF}" "${OUT}"
	done

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
else
	echo "==> Invalid file type!"
	exit 1
fi
