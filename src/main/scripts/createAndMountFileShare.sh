#!/bin/bash

function createAndMountFileShare()
{

  echo "Creating mount point"
  echo "Mount point: ${FILE_SHARE_MOUNT}"
  sudo mkdir -p ${FILE_SHARE_MOUNT}
  
  if [ ! -d "/etc/smbcredentials" ]; then
    sudo mkdir /etc/smbcredentials
  fi

  if [ ! -f "/etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred" ]; then
    echo "Crearing smbcredentials"
    echo "username=${STORAGE_ACCOUNT_NAME} >> /etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred"
    echo "password=${STORAGE_ACCOUNT_KEY} >> /etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred"
    sudo bash -c "echo "username=${STORAGE_ACCOUNT_NAME}" >> /etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred"
    sudo bash -c "echo "password=${STORAGE_ACCOUNT_KEY}" >> /etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred"
  fi

  echo "chmod 600 /etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred"
  sudo chmod 600 /etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred
  
  echo "//${STORAGE_ACCOUNT_NAME}.file.core.windows.net/${FILE_SHARE_NAME} ${FILE_SHARE_MOUNT} cifs nofail,vers=2.1,credentials=/etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred ,dir_mode=0777,file_mode=0777,serverino"
  sudo bash -c "echo \"//${STORAGE_ACCOUNT_NAME}.file.core.windows.net/${FILE_SHARE_NAME} ${FILE_SHARE_MOUNT} cifs nofail,vers=2.1,credentials=/etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred ,dir_mode=0777,file_mode=0777,serverino\" >> /etc/fstab"
  echo "mount -t cifs //${STORAGE_ACCOUNT_NAME}.file.core.windows.net/${FILE_SHARE_NAME} ${FILE_SHARE_MOUNT} -o vers=2.1,credentials=/etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred,dir_mode=0777,file_mode=0777,serverino"
  sudo mount -t cifs //${STORAGE_ACCOUNT_NAME}.file.core.windows.net/${FILE_SHARE_NAME} ${FILE_SHARE_MOUNT} -o vers=2.1,credentials=/etc/smbcredentials/${STORAGE_ACCOUNT_NAME}.cred,dir_mode=0777,file_mode=0777,serverino
  
  if [[ $? != 0 ]];
  then
         echo "Failed to mount //${STORAGE_ACCOUNT_NAME}.file.core.windows.net/${FILE_SHARE_NAME} ${FILE_SHARE_MOUNT}"
         exit 1
  else
        echo "//${STORAGE_ACCOUNT_NAME}.file.core.windows.net/${FILE_SHARE_NAME} successfully mounted on ${FILE_SHARE_MOUNT}"
        exit 0
  fi
}

function usage()
{
cat << USAGE >&2
Usage:
    -storageAccountName    STORAGE_ACCOUNT_NAME   Account Storage Name
    -storageAccountKey     STORAGE_ACCOUNT_KEY    Storage Account Key
    -fileShareName         FILE_SHARE_NAME            File Share Name
    -h|?|--help            HELP                   Help/Usage info
USAGE

exit 1
}

function get_param()
{
    while [ "$1" ]
    do
        case "$1" in    
              -h |?|--help )        usage ;;
       -storageAccountName )        STORAGE_ACCOUNT_NAME=$2 ;;
       -storageAccountKey  )        STORAGE_ACCOUNT_KEY=$2 ;;
       -fileShareName      )        FILE_SHARE_NAME=$2 ;;
                          *)        echo 'invalid arguments specified'
                                    usage;;
        esac
        shift 2
    done
}

function validate_input()
{

    if [[ $# -ne 6 ]];
    then
        usage
    fi

    if [ -z "$STORAGE_ACCOUNT_NAME" ];
    then
        echo "Storage Account Name not specified."
        usage
    fi

    if [ -z "$STORAGE_ACCOUNT_KEY" ];
    then
        echo "Storage Account Key not specified."
        usage
    fi

    if [ -z "$FILE_SHARE_NAME" ];
    then
        echo "File Share Name not specified."
        usage
    fi

}

#main

get_param "$@"

validate_input "$@"

FILE_SHARE_MOUNT="/mnt/$FILE_SHARE_NAME"

createAndMountFileShare
