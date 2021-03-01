#
# Generate temporary storage account and resource group
declare storageGroup=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 12 | head -n 1)
declare storageAccount=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 12 | head -n 1)
#
declare sqllogin=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 13  ; echo)
echo "##vso[task.setvariable variable=sqllogin]$sqllogin"
declare sqlpassword=$(tr -dc 'A-Za-z0-9!#$%&*+-=?@^_~' </dev/urandom | head -c 20  ; echo)
echo "##vso[task.setvariable variable=sqlpassword]$sqlpassword"
#
echo "Downloading $BACPACFILE..."
#
wget https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/$BACPACFILE
#
echo "Creating temporary Storage Account ..."
az storage account create -g $RG -n $storageAccount --sku Standard_LRS
#
echo "Getting created Storage Key..."
declare storageKey=$(az storage account keys list -g $RG -n $storageAccount --query "[0].value" -o tsv)
# export account account and key to
export AZURE_STORAGE_KEY=$storageKey
export AZURE_STORAGE_ACCOUNT=$storageAccount
#
echo "Creating Container..."
az storage container create -n "bacpac" 
#
echo "Uploading bacpac..."
az storage blob upload -f ./$BACPACFILE -c "bacpac" -n $BACPACFILE
#
echo "Creating Azure SQL database..."
az sql server create -l westus -g $RG -n $SQLSERVER -u $sqllogin -p $sqlpassword
#
if [ $AZUREDEVOPSSPNDBADMIN = 1 ]; then
    echo "add Azure DevOps SPN as SQL AAD admin"
    # get objectid and objectname of Azure DevOps SPN
    objectId=$(az ad signed-in-user show --query objectId --output tsv)
    objectName=$(az ad signed-in-user show --query userPrincipalName --output tsv)
    az sql server ad-admin create -u $objectName -i $objectId -g $RG -s $SQLSERVER
    #objectName=$(az account show --query user.name --output tsv)
    #az sql server ad-admin create -u $objectName -g $RG -s $SQLSERVER
else
    echo "add SQLMI as SQL AAD admin"
    az extension add --name datafactory
    api_response=$(az datafactory factory show -n $ADFV2NAME -g $RG)
    adfv2id=$(jq .identity.principalId -r <<< "$api_response")
    az sql server ad-admin create -u $ADFV2NAME -i $adfv2id -g $RG -s $SQLSERVER
fi
#
az sql server firewall-rule create -g $RG -s $SQLSERVER -n myrule --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255
az sql db create -g $RG -s $SQLSERVER -n $SQLDATABASE --service-objective $SQLSERVICEOBJECTIVE
#
echo "Importing bacpac..."
az sql db import\
    -g $RG \
    -s $SQLSERVER \
    -n $SQLDATABASE \
    -u $sqllogin \
    -p $sqlpassword \
    --storage-key-type StorageAccessKey \
    --storage-key $storageKey \
    --storage-uri https://$storageAccount.blob.core.windows.net/bacpac/$BACPACFILE
#   
#   
# Delete temporary resources
echo "Deleting temporary resources..."
az storage account delete -n $storageAccount -g $RG
#
echo "Done."