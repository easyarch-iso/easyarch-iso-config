# Source .profile from home directory to include common
# environmental variables and invoke exec statements
if [[ -f ~/.profile ]]; then
    . ~/.profile
fi

