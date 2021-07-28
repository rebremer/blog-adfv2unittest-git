# Create ADLSgen2 account and upload csv data
#
# 0. Check whether Storage was already deployed before (deployment takes ~2 minutes)
adlsexist=$(az storage account show -n $ADLSGEN2STOR -g $RG)
adlsname=$(jq .name -r <<< "$adlsexist")
if [[ $adlsname = $ADLSGEN2STOR && $REDEPLOYADLS = 0 ]]; then
   echo "ADLSgen2 storage account already exists and does not have to be redeployed"
   exit 0
fi
# 1. Create ADLSGen2 storage account
az storage account create -n $ADLSGEN2STOR -g $RG -l $LOC --sku Standard_LRS --kind StorageV2 --enable-hierarchical-namespace true
# 2. Create raw container and add csv data
az storage container create --account-name $ADLSGEN2STOR -n "raw"
az storage blob upload -f "data/AdultCensusIncome.csv" -c "raw" -n "AdultCensusIncome.csv" --account-name $ADLSGEN2STOR
# 3. Create raw container and add csv data
az storage container create --account-name $ADLSGEN2STOR -n "curated"
# 4. Grant ADFv2 MI access to storage account
az extension add --name datafactory
api_response=$(az datafactory show -n $ADFV2NAME -g $RG)
adfv2_id=$(jq .identity.principalId -r <<< "$api_response")
# Assign RBAC rights ADFv2 MI on storage account. 
# Service connection SPN needs to have owner rights on account
scope="/subscriptions/$SUBSCRIPTIONID/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$ADLSGEN2STOR"
az role assignment create --assignee-object-id $adfv2_id --role "Storage Blob Data Contributor" --scope $scope
