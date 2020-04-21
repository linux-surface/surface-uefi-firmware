#!/bin/sh

setmodel()
{
	BASENAME=$(basename $1)
	NEWNAME="$2_$(echo $BASENAME | cut -d'_' -f2-)"

	mv $1 $(dirname $1)/$NEWNAME
	echo " > New filename is $NEWNAME"
}

match()
{
	echo $1 | grep -q $2
}

FILE=$1
NAME=$(basename $FILE)
MODEL=""

if match $NAME SurfaceGo && match $NAME WiFi; then
	setmodel $FILE SurfaceGo-WiFi
	exit
fi

if match $NAME SurfaceGo && match $NAME LTE; then
	setmodel $FILE SurfaceGo-LTE
	exit
fi

# Matching for SurfacePro_ avoids any false positives when checking
# other Surface Pros with proper naming on their firmware MSIs
if match $NAME SurfacePro_ && match $NAME LTE; then
	setmodel $FILE SurfacePro5-LTE
	exit
fi

if match $NAME SurfacePro_; then
	setmodel $FILE SurfacePro5-WiFi
	exit
fi

echo " > No changes neccessary! Filename stays $NAME"
