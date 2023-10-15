#!/bin/bash
set -euo pipefail

# GLOBALS
declare -g FILE=""
declare -g OUTPUT="fwupdates"
declare -g CAB_ARRAY=()

usage()
{
	echo "Usage: $0 <FILE> [OUTPUTDIR]"
	echo "Repackages Microsoft Surface firmware for fwupd"
	echo
	echo "Arguments:"
	echo "    FILE       The file to repack"
	echo "                 (can be .msi, .cab, .inf, or a directory)"
	echo "    OUTPUTDIR  The directory where to save the output"
	echo "               (Optional; default is '$OUTPUT')"
	echo "Options:"
	echo "    -h         This help message"
}


# For backwards compatibility, allow -f and -o flags.
eval set -- "$(getopt -o 'hf:o:' --long 'help,input:,output:' -- "$@")"
while true; do
	case "${1}" in
	-f|--input)
		FILE="$2"
		shift 2
		;;
	-o|--output)
		OUTPUT="$2"
		shift 2
		;;
	-h|--help)
		usage
		exit
		;;
	--)
		shift
		break
		;;
	*)
		echo "ERROR: Invalid command line option '${1}'"
		exit 1
		;;
	esac
done

if [ "$FILE" = "" -a $# -gt 0 ]; then
    FILE="${1}"
    shift
fi

if [ "$#" -gt 0 ]; then
    OUTPUT="${1}"
    shift
fi

if [ "$#" -gt 0 ]; then
    echo "ERROR: Excess arguments: $@"
    exit 1
fi

if [ "$FILE" = "" ]; then
	echo "ERROR: No filename specified!"
	usage
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
    fi
done


main()
{
    mkdir -p "${OUTPUT}"

    case "${FILE}" in
	*.msi) repackmsi "${FILE}" "${OUTPUT}"
	       ;;
	*.cab) repackcab "${FILE}" "${OUTPUT}"
	       ;;
	*.inf) repackinf "${FILE}" "${OUTPUT}"
	       ;;
	*) if [ -d "${FILE}" ]; then
	       repackdir "${FILE}" "${OUTPUT}"
	   else
	       echo "==> ${FILE}: Invalid file type!"
	       exit 1
	   fi
    esac

    if [[ ${#CAB_ARRAY[@]} -gt 0 ]]; then
	echo "Success!"
	echo "If you wish, you may now install the firmware like so:"
	echo
	local f
	for f in "${CAB_ARRAY[@]}"; do
	    echo -n "  sudo fwupdmgr install --allow-older --no-reboot-check --force "
	    echo "'$f'"
	done
    else
	echo "No firmware found in '${FILE}'"
    fi	
}    


repackinf()
{
	# Parse parameters
	local INF="${1}"
	local OUT="${2}"

	# What is the name of the firmware?
	local DIR="$(dirname "${INF}")"
	local FIRMWARE="$(basename "${DIR}")"

	# Create a working directory
	local TEMP="$(mktemp -p . -d)"

	# Copy over files
	local BINFILE CATFILE INFFILE
	BINFILE="$(find "${DIR}" \( -iname '*.bin' -or -iname '*.cap' \) -print -quit)"
	CATFILE="$(find "${DIR}" -iname '*.cat' -print -quit)"
	INFFILE="$(find "${DIR}" -iname '*.inf' -print -quit)"

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

	# Update the device GUID
	local -l DEVICE		# -l: Values are always lowercase
	DEVICE="$(awk -F'[{}]' '/Firmware_Install, *UEFI/{print $2}' "${TEMP}/firmware.inf")"

	# Update firmware type
	local CATEGORY
	case "$(basename "${INFFILE}")" in
	    *UEFI*) 	CATEGORY="X-System"		;;
	    *ME*)	CATEGORY="X-ManagementEngine"	;;
	    *)		CATEGORY="X-Device"		;;
	esac

	# Update firmware version
	local VERSION
	VERSION="$(grep FirmwareVersion "${TEMP}/firmware.inf" | cut -d, -f5)"
	VERSION=${VERSION%$'\r\n'}
	local MAJOR="$(( (VERSION >> 24) & 0xff ))"
	local MINOR="$(( (VERSION >> 16) & 0xff ))"
	local REV="$(( VERSION & 0xffff ))"
	VERSION="${MAJOR}.${MINOR}.${REV}"

	# Update firmware timestamp
	local TIMESTAMP
	TIMESTAMP="$(awk -F'[=,]' '/^DriverVer/{print $2}' "${TEMP}/firmware.inf")"
	TIMESTAMP="$(date '+%s' --date "${TIMESTAMP}")"

	# Create metainfo file from $DEVICE, $CATEGORY, $VERSION, & $TIMESTAMP
	filltemplate "$DEVICE" "$CATEGORY" "$VERSION" "$TIMESTAMP" \
		     > "${TEMP}/firmware.metainfo.xml"

	# Create a cab file of the firmware
	local cabfile="${OUT}/${FIRMWARE}_${VERSION}_${DEVICE}.cab"
	gcab -cn "$cabfile" "${TEMP}"/*
	rm -r "${TEMP}"
	
	# Remember the cab filename for later
	CAB_ARRAY+=($cabfile)
}

repackdir()
{
	local DIR="${1}"
	local OUT="${2}"

	# Convert all .inf files to unix format
	find "${DIR}" -iname '*.inf' -exec sh -c 'dos2unix "$0" > /dev/null 2>&1' {} \;

	# Repack all UEFI capsule updates found in the directory
	local inffiles=($(grep -lR 'Firmware_Install,UEFI' "${DIR}"))
	for INF in ${inffiles[@]}; do
		echo "==> Repacking ${INF}"

		repackinf "${INF}" "${OUT}"
	done
}

repackmsi()
{
	local MSI="${1}"
	local OUT="${2}"

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
	local CAB="${1}"
	local OUT="${2}"

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

filltemplate()
{
    # Fill in the XML template
    local DEVICE="$1" CATEGORY="$2" VERSION="$3" TIMESTAMP="$4"
    cat <<EOF 
<?xml version="1.0" encoding="UTF-8"?>
<component type="firmware">
	<id>com.surfacelinux.firmware.${DEVICE}</id>
	<provides>
		<firmware type="flashed">${DEVICE}</firmware>
	</provides>
	<name>Surface Firmware</name>
	<summary>Firmware for ${DEVICE}</summary>
	<description>
		<p>Updating the firmware on your device improves performance and adds new features.</p>
	</description>
	<categories>
		<category>${CATEGORY}</category>
	</categories>
	<custom>
		<value key="LVFS::UpdateProtocol">org.uefi.capsule</value>
	</custom>
	<url type="homepage">https://www.microsoft.com</url>
	<metadata_license>CC0-1.0</metadata_license>
	<project_license>proprietary</project_license>
	<developer_name>Microsoft</developer_name>
	<releases>
		<release version="${VERSION}" timestamp="${TIMESTAMP}">
			<description>
				<p>Please visit the Microsoft homepage to find more information about this update.</p>
				<p>The computer will be restarted automatically after updating completely. Do NOT turn off your computer or remove the AC adaptor while update is in progress.</p>
			</description>
		</release>
	</releases>
</component>
EOF

}

main "$@"

