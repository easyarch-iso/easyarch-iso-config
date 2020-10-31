#!/bin/bash
###############################################################################################
#
#   Script to check the existence of samba usershare folder and its permissions.
#   If the folder doesnt exist it will created with the right permissions.
#   If it already exists, its permission will be corrected if needed.
#   
#
###############################################################################################

SAMBASHARE_DIR=/var/lib/samba/usershares

if [[ $EUID -ne 0 ]]; then
    echo Configuring samba user share requires root privilege
    exit -1
fi

if [[ -d $SAMBASHARE_DIR ]]; then
    chown root:sambashare $SAMBASHARE_DIR
    chmod 1770 $SAMBASHARE_DIR
else
    mkdir -pv $SAMBASHARE_DIR
    chown root:sambashare $SAMBASHARE_DIR
    chmod 1770 $SAMBASHARE_DIR
fi
