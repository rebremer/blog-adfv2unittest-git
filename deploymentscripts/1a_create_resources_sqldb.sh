# Create SQL database and restore BACPAC
#
# 0. Check whether SQL server was already deployed before (deployment takes ~10 minutes)
sqlexist=$(az sql server show -n $SQLSERVER -g $RG)
sqlname=$(jq .name -r <<< "$sqlexist")
if [[ $sqlname = $SQLSERVER && $REDEPLOYSQLDB = 0 ]]; then
   echo "SQLServer already exists and does not have to be redeployed"
   exit 0
fi
#
# 1. Create temporary storage account and upload BACPAC
tmpStorageAccount=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 12 | head -n 1)
az storage account create -g $RG -n $tmpStorageAccount --sku Standard_LRS
az storage container create -n "bacpac" --account-name $tmpStorageAccount
az storage blob upload -f "data/"$BACPACFILE -c "bacpac" -n $BACPACFILE --account-name $tmpStorageAccount
#
# 2. Create a SQL account
sqlpassword=$(tr -dc 'A-Za-z0-9!' </dev/urandom | head -c 20  ; echo)
# echo keys since there are needed in test phase
#echo "##vso[task.setvariable variable=sqllogin]$sqllogin"
#echo "##vso[task.setvariable variable=sqlpassword]$sqlpassword"
az sql server create -l $LOC -g $RG -n $SQLSERVER -u $SQLLOGIN -p $sqlpassword
#
# In case Azure DevOps SPN will be SQL admin, then add it as AAD admin, otherwise add the ADFv2 MI as AAD admin
if [ $AZUREDEVOPSSPNDBADMIN = 1 ]; then
    # Azure Devops SPN as SQL AAD admin
    echo "add Azure DevOps SPN as SQL AAD admin"
    # get objectid and objectname of Azure DevOps SPN
    objectId=$(az ad signed-in-user show --query objectId --output tsv)
    objectName=$(az ad signed-in-user show --query userPrincipalName --output tsv)
    az sql server ad-admin create -u $objectName -i $objectId -g $RG -s $SQLSERVER
else
    # ADFv2 SPN as SQL AAD admin
    echo "add ADFv2 MI as SQL AAD admin"
    az extension add --name datafactory
    api_response=$(az datafactory show -n $ADFV2NAME -g $RG)
    adfv2id=$(jq .identity.principalId -r <<< "$api_response")
    az sql server ad-admin create -u $ADFV2NAME -i $adfv2id -g $RG -s $SQLSERVER
fi
#
az sql server firewall-rule create -g $RG -s $SQLSERVER -n myrule --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255
az sql db create -g $RG -s $SQLSERVER -n $SQLDATABASE --service-objective $SQLSERVICEOBJECTIVE
#
# 3. Restore BacPac file
echo "Importing bacpac..."
storageKey=$(az storage account keys list -g $RG -n $tmpStorageAccount --query "[0].value" -o tsv)
az sql db import\
    -g $RG \
    -s $SQLSERVER \
    -n $SQLDATABASE \
    -u $SQLLOGIN \
    -p $sqlpassword \
    --storage-key-type StorageAccessKey \
    --storage-key $storageKey \
    --storage-uri https://$tmpStorageAccount.blob.core.windows.net/bacpac/$BACPACFILE
#   
# 4. Remove temporary storage account
echo "Deleting temporary resources..."
az storage account delete -n $tmpStorageAccount -g $RG
#
echo "Done."
