tokenadf=$(az account get-access-token --resource=https://management.core.windows.net/ --query accessToken --output tsv)
tokendb=$(az account get-access-token --resource=https://database.windows.net/ --query accessToken --output tsv)
echo "##vso[task.setvariable variable=tokenadf]$tokenadf"
echo "##vso[task.setvariable variable=tokendb]$tokendb"
# Datafactory
az extension add --name datafactory
api_response=$(az datafactory factory show -n $ADFV2NAME -g $RG)
adfv2id=$(jq .identity.principalId -r <<< "$api_response")
echo "##vso[task.setvariable variable=adfv2id]$adfv2id"