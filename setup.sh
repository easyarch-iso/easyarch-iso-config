#!/bin/bash

# Global variables
PWD=$(pwd)
TODAY=$(date +'%d-%m-%Y')
ARCH=$(uname -m)
SYS_ARCHISO_DIR=/usr/share/archiso/configs/releng
LIVE_AIROOTFS=$PWD/airootfs
LIVE_EXTRA_PKG_LIST=$PWD/live_extra_packages.x86_64
WORK_DIR=$(readlink -m $PWD/../ISO_WORK-$TODAY)
ARCHISO_DIR=
AUR_DIR=
AUR_DIR_SPECIFIED=0
LOCAL_REPO_DIR=
LOCAL_REPO_DIR_SPECIFIED=0
AUR_PKG_CONFIG=
AUR_PKG_CONFIG_SPECIFIED=0
AUR_PKG_LIST=
AUR_PKG_LIST_SPECIFIED=0

# Command line switch variables
CHECK_ARCHISO=1
BUILD_AUR_PKGS=1
BUILD_LOCAL_REPO=1
PREPARE_ARCHISO=1

update_globals() {
    ARCHISO_DIR=$WORK_DIR/archiso
    if [[ $AUR_DIR_SPECIFIED == 0 ]]; then
        AUR_DIR=$WORK_DIR/aur-pkgs
    fi
    if [[ $LOCAL_REPO_DIR_SPECIFIED == 0 ]]; then
        LOCAL_REPO_DIR=$WORK_DIR/localrepo
    fi
    if [[ $AUR_PKG_CONFIG_SPECIFIED == 0 ]]; then
        AUR_PKG_CONFIG=$PWD/aurpkgs
    fi
    if [[ $AUR_PKG_LIST_SPECIFIED == 0 ]]; then
        AUR_PKG_LIST=$WORK_DIR/aur_pkg_list
    fi
}

# checks if archiso package is installed. 
# if not installed installs the package and creates a 
# copy of SYS_ARCHISO_DIR in ARCHISO_DIR.
check_archiso() {
    # check archiso package installed or not
    if [[ -d $SYS_ARCHISO_DIR ]]; then
        echo Archiso is installed.
    else
        echo Archiso is not installed. Installing...
        sudo pacman -Syy & sudo pacman -S --noconfirm archiso
    fi
    
    # if old ARCHISO_DIR exists ask user if he wants to
    # delete it or not. if it doesnt already exist, then
    # create it and copy contents of SYS_ARCHISO_DIR in it.
    if [[ -d $ARCHISO_DIR ]]; then
        read -rp "Old iso build dir exists. Delete it (Y/N)? " choice
        case $choice in
            y|Y|yes|Yes|YES)
                echo "Deleting $ARCHISO_DIR..."
                sudo rm -rf "$ARCHISO_DIR"
                sudo cp -r "$SYS_ARCHISO_DIR" "$ARCHISO_DIR"
                echo "$ARCHISO_DIR is created and set up."
                ;;
            *)
                echo "Leaving $ARCHISO_DIR as it is..."
                ;;
        esac
    else
        echo "$ARCHISO_DIR does not exist."
        mkdir -pv "$WORK_DIR"
        sudo cp -r "$SYS_ARCHISO_DIR" "$ARCHISO_DIR"
        echo "$ARCHISO_DIR is created and set up."
    fi
}

# builds an aur packaged by downloading
# PKGBUILD and running makepkg command. Additionally
# it also copies the result package in the localrepo directory.
# additionally it adds the package name to AUR_PKG_LIST file
# for later usage.
# 
# Usage-
#   build_aur_pkg <packge_name> <pkgbuild_git_repo>
build_aur_pkg() {
    if [[ ! -d $LOCAL_REPO_DIR ]]; then
        echo Local repo directory does not exist. Creating it...
        mkdir -pv $LOCAL_REPO_DIR
    fi
    if [[ ! -d $AUR_DIR ]]; then
        echo AUR package build directory does not exist. Creating it...
        mkdir -pv $AUR_DIR
    fi
    
    if [[ -d $AUR_DIR/$1 ]]; then
        cd $AUR_DIR/$1 || return
        git pull --ff-only
        cd $PWD || return
    else
        git clone $2 $AUR_DIR/$1
    fi
    
    if [[ ! -d $AUR_DIR/$1 ]]; then
        return
    fi
    
    cd $AUR_DIR/$1 || return
    echo Build log will be saved in build.log file.
    makepkg &> build.log
    pkgfile=$(ls $AUR_DIR/$1 | grep zst)
    if [[ ! -n $pkgfile ]]; then
        echo Failed to build $1. Exiting...
        exit 1
    fi
    cp -v $pkgfile $LOCAL_REPO_DIR/
    cd $PWD || return
    if [[ ! -f $AUR_PKG_LIST ]]; then
        touch $AUR_PKG_LIST
    fi
    if grep -Fxq "$1" $AUR_PKG_LIST; then
        echo $1 is already listed in aur pkg list.
    else
        echo Enlisting $1 in the aur pkg list...
        echo $1 >> $AUR_PKG_LIST
    fi
}

# builds local repo by adding existing packages in
# repo db within LOCAL_REPO_DIR. so AUR packages
# should be built and copied there already.
build_local_repo() {
    echo Building local repository...
    if [[ ! -d $LOCAL_REPO_DIR ]]; then
        echo $LOCAL_REPO_DIR does not exist. Exiting...
        exit 1
    fi
    cd $LOCAL_REPO_DIR || return
    repo-add localrepo.db.tar.xz *.zst
    cd $PWD || exit 1
}

# prepares the archiso directory for the final
# build process. this step mostly, copies files and
# customizes package list etc. this does not actually
# build the iso, it only prepares the ARCHISO_DIR for
# running the build script.
prepare_archiso() {
    echo Preparing archiso for final build...
    
    # step 1 - copy airootfs to archiso/airootfs and fix some paths and permissions
    sudo cp -rfvT --no-dereference --preserve=links $LIVE_AIROOTFS $ARCHISO_DIR/airootfs
    sudo mv -fv $ARCHISO_DIR/airootfs/etc/skel/.oh-my-zsh/{_,.}git
    sudo mv -fv $ARCHISO_DIR/airootfs/etc/skel/.oh-my-zsh/{_,.}github
    sudo mv -fv $ARCHISO_DIR/airootfs/etc/skel/.oh-my-zsh/{_,.}gitignore
    sudo mv -fv $ARCHISO_DIR/airootfs/etc/skel/.oh-my-zsh/custom/themes/powerlevel10k/{_,.}git
    sudo mv -fv $ARCHISO_DIR/airootfs/etc/skel/.oh-my-zsh/custom/themes/powerlevel10k/{_,.}gitignore
    sudo mv -fv $ARCHISO_DIR/airootfs/etc/skel/.oh-my-zsh/custom/themes/powerlevel10k/{_,.}gitattributes
    sudo chmod +x $ARCHISO_DIR/airootfs/usr/bin/sambashare-config.sh
    sudo chmod +x $ARCHISO_DIR/airootfs/usr/local/bin/aurpkg.sh
    
    # step 2 - add extra live iso packages
    if [[ -f $LIVE_EXTRA_PKG_LIST ]]; then
        while read line; do
            if ! grep -Fxq "$line" $ARCHISO_DIR/packages.x86_64; then
                sudo bash -c "echo '$line' >> $ARCHISO_DIR/packages.x86_64"
            fi
        done < $LIVE_EXTRA_PKG_LIST
    fi
    
    # step 3 - add local repo to archiso build
    if grep -Fxq '[localrepo]' $ARCHISO_DIR/pacman.conf; then
        echo Local repository is already in pacman.conf.
    else
        sudo bash -c "echo '[localrepo]' >> $ARCHISO_DIR/pacman.conf"
        sudo bash -c "echo 'SigLevel = Optional TrustAll' >> $ARCHISO_DIR/pacman.conf"
        sudo bash -c "echo 'Server = file://$LOCAL_REPO_DIR' >> $ARCHISO_DIR/pacman.conf"
    fi
    
    # step 4 - add aur packages to live iso package list
    if [[ -f $AUR_PKG_LIST ]]; then
        while read line; do
            if ! grep -Fxq "$line" $ARCHISO_DIR/packages.x86_64; then
                sudo bash -c "echo '$line' >> $ARCHISO_DIR/packages.x86_64"
            fi
        done < $AUR_PKG_LIST
    fi
        
    # step 5 - remove conflicting package from the pkg list
    sudo sed -i s%grml-zsh-config%%g $ARCHISO_DIR/packages.x86_64
    
    # print a result 
    isodate=$(date +'%Y.%m.%d')
    echo 
    echo
    echo ----------------------------------------------------------------
    echo You are all set to build archiso.
    echo Run the following commands to build your iso -
    echo
    echo "  cd '$ARCHISO_DIR'"
    echo "  sudo mkarchiso -v ."
    echo
    echo Note: If build command fails for package integrity error, just
    echo rerun the command.
    echo
    echo After successful ISO build run it with this command -
    echo 
    echo "  run_archiso -i '$ARCHISO_DIR/out/archlinux-$isodate-$ARCH.iso'" 
    echo
    echo Enjoy your own built iso !
    echo ----------------------------------------------------------------
    echo 
    echo
}

# simple help screen.
help() {
    echo Usage: setup.sh OPTIONS
    echo Archiso preparation script.
    echo
    echo OPTIONS -
    echo "  --work-dir DIR         Work directory where all build files will be in. Default: $WORK_DIR"
    echo "  --aur-dir DIR          Directory for AUR pkg building. Default: $AUR_DIR"
    echo "  --local-repo-dir DIR   Directory for creating local repository. Default: $LOCAL_REPO_DIR"
    echo "  --aur-pkgs FILEPATH    AUR package list to add to local repo. Default: $AUR_PKG_CONFIG"
    echo "  --aur-pkg-list FILE    AUR package list to add to ISO. Default: $AUR_PKG_LIST"
    echo "  --no-check-archiso     Skip checking archiso installation."
    echo "  --no-build-aur-pkgs    Skip building AUR packages."
    echo "  --no-build-local-repo  Skip building local repo."
    echo "  --no-prepare-archiso   Skip archiso preparation step."
    echo "  --help,-h              Print this help and exit."
}

# check host machine architecture, it has to be x86_64
if [[ $ARCH != "x86_64" ]]; then
    echo You need to run this setup script on a x86_64 machine.
    exit 1
fi

# read the command line switches
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key=$1
    case $key in
        --work-dir)
            WORK_DIR=$(readlink -m "$2")
            shift
            shift
            ;;        
        --no-check-archiso)
            CHECK_ARCHISO=0
            shift
            ;;
        --no-build-aur-pkgs)
            BUILD_AUR_PKGS=0
            shift
            ;;
        --no-build-local-repo)
            BUILD_LOCAL_REPO=0
            shift
            ;;
        --no-prepare-archiso)
            PREPARE_ARCHISO=0
            shift
            ;;
        --aur-dir)
            AUR_DIR=$(readlink -m "$2")
            AUR_DIR_SPECIFIED=1
            shift
            shift
            ;;
        --local-repo-dir)
            LOCAL_REPO_DIR=$(readlink -m "$2")
            LOCAL_REPO_DIR_SPECIFIED=1
            shift
            shift
            ;;
        --aur-pkgs)
            AUR_PKG_CONFIG=$(readlink -m "$2")
            AUR_PKG_CONFIG_SPECIFIED=1
            shift
            shift
            ;;
        --aur-pkg-list)
            AUR_PKG_LIST=$(readlink -m "$2")
            AUR_PKG_LIST_SPECIFIED=1
            shift
            shift
            ;;
        --help|-h)
            update_globals
            help
            exit 0
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
# check for unknown arguments by checking remaing positional args list
set -- "${POSITIONAL[@]}" # restore positional parameters
if [[ -n $1 ]]; then
    echo "Unknown argument $1"
    help
    exit 1
fi

# Update global variables
update_globals

echo Setup flags -
echo "  WORK_DIR=$WORK_DIR"
echo "  CHECK_ARCHISO=$CHECK_ARCHISO"
echo "  BUILD_AUR_PKGS=$BUILD_AUR_PKGS"
echo "  BUILD_LOCAL_REPO=$BUILD_LOCAL_REPO"
echo "  PREPARE_ARCHISO=$PREPARE_ARCHISO"
echo "  AUR_PKG_CONFIG=$AUR_PKG_CONFIG"
echo "  AUR_PKG_LIST=$AUR_PKG_LIST"
echo "  AUR_DIR=$AUR_DIR"
echo "  LOCAL_REPO_DIR=$LOCAL_REPO_DIR"
echo

# we are all set for preparing archiso.

if [[ $CHECK_ARCHISO == 1 ]]; then
    check_archiso
fi

if [[ $BUILD_AUR_PKGS == 1 ]]; then    
    while IFS=';' read -a PKG -r; do
        [ -z "${PKG[0]}" ] && continue
        if echo "${PKG[0]}" | grep -q '#' ; then
            continue
        fi
        # remove extra space chars from the lines
        name=$(echo "${PKG[0]}" | sed -e 's/^[[:space:]]*//' )
        url=$(echo "${PKG[1]}" | sed -e 's/^[[:space:]]*//' )
        build_aur_pkg "$name" "$url"
    done < $AUR_PKG_CONFIG
fi

if [[ $BUILD_LOCAL_REPO == 1 ]]; then
    build_local_repo
fi

if [[ $PREPARE_ARCHISO == 1 ]]; then
    prepare_archiso
fi
