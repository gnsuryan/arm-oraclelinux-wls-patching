#!/bin/bash


function usage()
{
cat << USAGE >&2
Usage:
    -resourceGroupName     RESOURCE_GROUP_NAME    Resource Group Name
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

    if [[ $# -ne 4 ]];
    then
        usage
    fi

}

function get_storage_account()
{
  STORAGE_ACCOUNT_NAME=$(az storage account list --resource-group "${RESOURCE_GROUP_NAME}" --query '[0].name' | tr -d '"')
}

function get_storage_account_key()
{
  STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group "${RESOURCE_GROUP_NAME}" --account-name "$STORAGE_ACCOUNT_NAME" --query '[0].value' | tr -d '"')
}

function check_and_create_file_share()
{
    az storage share list --account-key "${STORAGE_ACCOUNT_KEY}" --account-name "${STORAGE_ACCOUNT_NAME}" --query '[].name' | grep "${AZURE_WLS_FILE_SHARE}"

    if [[ $? != 0 ]];
    then
        echo "File Share ${AZURE_WLS_FILE_SHARE} does not exists on Storage Account: ${STORAGE_ACCOUNT_NAME}"
        echo "creating and mounting File Share ${AZURE_WLS_FILE_SHARE} ..."
        createAndMountFileShare
    else
        echo "File Share ${AZURE_WLS_FILE_SHARE} exists on Storage Account: ${STORAGE_ACCOUNT_NAME}"
    fi

    check_and_create_patch_directory
}

function check_and_create_patch_directory()
{
    result=$(az storage directory exists --name ${PATCH_DIR} --share-name ${AZURE_WLS_FILE_SHARE} --account-key ${STORAGE_ACCOUNT_KEY} --account-name ${STORAGE_ACCOUNT_NAME}  --query 'exists')

    if [ "$result" == "false" ];
    then
        echo "Patch Directory not found in WLS Azure File Storage: ${AZURE_WLS_FILE_SHARE}"
        echo "Creating  Patch Directory in WLS Azure File Storage: ${AZURE_WLS_FILE_SHARE}"
        result=$(az storage directory create --name ${PATCH_DIR} --share-name ${AZURE_WLS_FILE_SHARE} --account-key ${STORAGE_ACCOUNT_KEY} --account-name ${STORAGE_ACCOUNT_NAME} --query 'created')
        if [ "$result" == "false" ];
        then
            echo "Unable to create Patch Directory in WLS Azure File Storage: ${AZURE_WLS_FILE_SHARE}"
            exit 1
        else
            echo "Patch Directory ${PATCH_DIR} successfully created in WLS Azure File Storage: ${AZURE_WLS_FILE_SHARE}"
        fi
    else
        echo "Patch Directory ${PATCH_DIR} already exists in WLS Azure File Storage: ${AZURE_WLS_FILE_SHARE}"
    fi
}


function upload_file_to_fileshare()
{
    az storage file upload --share-name ${AZURE_WLS_FILE_SHARE} --source ${LOCAL_FILE_PATH} --account-key ${STORAGE_ACCOUNT_KEY} --account-name ${STORAGE_ACCOUNT_NAME} --path ${PATCH_DIR}

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
    result=$(az storage share create --name ${AZURE_WLS_FILE_SHARE} --quota 10 --account-name ${STORAGE_ACCOUNT_NAME} --account-key ${STORAGE_ACCOUNT_KEY} --query 'created')

    if [ "$result" == "true" ];
    then
        echo "WLS Azure File Share created: ${AZURE_WLS_FILE_SHARE}"

        if [ "$(az vm list -d -o table --query "[?name=='adminVM']")" = "" ];
        then
            echo "VM with name admin VM was found. "
            VM_NAME="adminVM"
        else
            echo "VM with name admin VM not found. This should be a Single node offer"
            VM_NAME="WebLogicServerVM"
        fi

        az vm run-command invoke -g ${RESOURCE_GROUP_NAME} -n $VM_NAME --command-id RunShellScript --scripts "wget https://raw.githubusercontent.com/gnsuryan/arm-oraclelinux-wls-patching/temp/createAndMountFileShare.sh; chmod +x createAndMountFileShare.sh; ./createAndMountFileShare.sh -storageAccountName ${STORAGE_ACCOUNT_NAME} -storageAccountKey ${STORAGE_ACCOUNT_KEY} -fileShareName ${AZURE_WLS_FILE_SHARE}"
    else
        echo "Failed to create WLS Azure File Share: ${AZURE_WLS_FILE_SHARE}"
        exit 1
    fi
}


#main

AZURE_WLS_FILE_SHARE="wlsshare"
PATCH_DIR="patches"
WLS_FILE_SHARE_MOUNT="/mnt/${AZURE_WLS_FILE_SHARE}"

validate_input "$@"

get_param "$@"

get_storage_account

get_storage_account_key

check_and_create_file_share

upload_file_to_fileshare

