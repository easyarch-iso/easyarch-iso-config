#!/bin/bash
_USER=$1
_GROUP=$2
PKG=$3
PKGTAR=$4
PKGURL=$5
CACHEDIR="/var/cache/aurpkg"

if [[ $EUID != 0 ]]; then
    echo Need to be root to run this script.
    exit -1
fi

if [[ -d $CACHEDIR ]]; then
    rm -rf $CACHEDIR
fi

mkdir -pv $CACHEDIR
chmod a+w $CACHEDIR
chown $_USER:$_GROUP $CACHEDIR
_PWD=$(pwd)
cd $CACHEDIR
su $_USER -c "curl $PKGURL -o $PKGTAR"
su $_USER -c "tar xf $PKGTAR -o $PKG"
cd $PKG
su $_USER -c makepkg
pacman -U --noconfirm *.zst
cd "$_PWD"
rm -rf "$CACHEDIR"

