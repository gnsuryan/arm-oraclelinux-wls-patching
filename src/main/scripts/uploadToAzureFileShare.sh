#!/bin/bash


function usage()
{
cat << USAGE >&2
Usage:
    -resourceGroupName     RESOURCE_GROUP_NAME    Resource Group Name
    -storageAccountName    STORAGE_ACCOUNT_NAME   Account Storage Name
    -localFilePath         LOCAL_FILE_PATH        Path of Local File to Upload
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
        -resourceGroupName )        RESOURCE_GROUP_NAME=$2 ;;
       -storageAccountName )        STORAGE_ACCOUNT_NAME=$2 ;;
            -localFilePath )        LOCAL_FILE_PATH=$2 ;;
                          *)        echo 'invalid arguments specified'
                                    usage;;
        esac
        shift 2
    done
}

function validate_input()
{

    az account list > /dev/null

    if [[ $? != 0 ]];
    then
       echo "Not logged on to Azure CLI. Please login first using 'az login' command and then try again."
       exit 1
    fi

    if [[ $# -ne 6 ]];
    then
        usage
    fi

}

function get_storage_account_key()
{
  STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group "${RESOURCE_GROUP_NAME}" --account-name "$STORAGE_ACCOUNT_NAME" --query '[0].value' | tr -d '"')
}

function check_fileshare_exists_on_storage_account()
{
    az storage share list --account-key "${STORAGE_ACCOUNT_KEY}" --account-name "${STORAGE_ACCOUNT_NAME}" --query '[].name' | grep "${AZURE_WLS_FILE_SHARE}"

    if [[ $? == 0 ]];
    then
        echo "File Share ${AZURE_WLS_FILE_SHARE} exists on Storage Account: ${STORAGE_ACCOUNT_NAME}"

    else
        echo "File Share ${AZURE_WLS_FILE_SHARE} does not exists on Storage Account: ${STORAGE_ACCOUNT_NAME}"
        echo "creating and mounting File Share ${AZURE_WLS_FILE_SHARE} ..."
        createAndMountFileShare
    fi
}

function upload_file_to_fileshare()
{
    az storage file upload --share-name ${AZURE_WLS_FILE_SHARE} --source ${LOCAL_FILE_PATH} --account-key ${STORAGE_ACCOUNT_KEY} --account-name ${STORAGE_ACCOUNT_NAME}

    if [[ $? == 0 ]];
    then
        echo "File Upload to Azure File Share completed successfully"
        exit 0
    else
        echo "File Upload to Azure File Share failed. Please try again"
        exit 1
    fi
}

# Mount the Azure file share on all VMs created
function createAndMountFileShare()
{
    az storage share create --name ${AZURE_WLS_FILE_SHARE} --quota 10 --account-name ${STORAGE_ACCOUNT_NAME} --account-key ${STORAGE_ACCOUNT_KEY}
    az vm run-command invoke -g ${RESOURCE_GROUP_NAME} -n adminVM --command-id RunShellScript --scripts "wget https://raw.githubusercontent.com/gnsuryan/arm-oraclelinux-wls-patching/master/src/main/scripts/createAndMountFileShare.sh; chmod +x createAndMountFileShare.sh; ./createAndMountFileShare.sh -storageAccountName ${STORAGE_ACCOUNT_NAME} -storageAccountKey ${STORAGE_ACCOUNT_KEY} -fileShareName ${AZURE_WLS_FILE_SHARE}"
}


#main

AZURE_WLS_FILE_SHARE="wlsshare"
WLS_FILE_SHARE_MOUNT="/mnt/${AZURE_WLS_FILE_SHARE}"

validate_input "$@"

get_param "$@"

get_storage_account_key

check_fileshare_exists_on_storage_account

upload_file_to_fileshare

