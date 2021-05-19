tokenadf=$(az account get-access-token --resource=https://management.core.windows.net/ --query accessToken --output tsv)
tokendb=$(az account get-access-token --resource=https://database.windows.net/ --query accessToken --output tsv)
#tokenadls=$(az account get-access-token --resource=https://storage.azure.com/ --query accessToken --output tsv)
echo "##vso[task.setvariable variable=tokenadf]$tokenadf"
echo "##vso[task.setvariable variable=tokendb]$tokendb"
#echo "##vso[task.setvariable variable=tokenadls]$tokenadls"
# Datafactory
az extension add --name datafactory
api_response=$(az datafactory show -n $ADFV2NAME -g $RG)
adfv2id=$(jq .identity.principalId -r <<< "$api_response")
echo "##vso[task.setvariable variable=adfv2id]$adfv2id"
# SQLDB
sqlpassword=$(tr -dc 'A-Za-z0-9!' </dev/urandom | head -c 20  ; echo)
az sql server update --admin-password $sqlpassword --name $SQLSERVER --resource-group $RG
echo "##vso[task.setvariable variable=sqlpassword]$sqlpassword"
# ADLSGen2 storage
accesskeyadls=$(az storage account keys list -g $RG -n $ADLSGEN2STOR --query "[0].value" -o tsv)
echo "##vso[task.setvariable variable=accesskeyadls]$accesskeyadls"
