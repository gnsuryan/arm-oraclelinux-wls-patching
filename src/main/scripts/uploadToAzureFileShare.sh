#!/bin/bash


usage()
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

get_param()
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

validate_input()
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


#main


validate_input "$@"

get_param "$@"

AZURE_WLS_FILE_SHARE="wlsshare"

AZURE_STORAGE_KEY=$(az storage account keys list --resource-group "$RESOURCE_GROUP_NAME" --account-name "$STORAGE_ACCOUNT_NAME" --query '[0].value' | tr -d '"')

az storage file upload --share-name $AZURE_WLS_FILE_SHARE --source $LOCAL_FILE_PATH --account-key $AZURE_STORAGE_KEY --account-name $STORAGE_ACCOUNT_NAME

if [[ $? == 0 ]];
then
    echo "File Upload to Azure File Share completed successfully"
    exit 0
else
    echo "File Upload to Azure File Share failed. Please try again"
    exit 1
fi

