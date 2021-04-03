import pytest
import os
import requests
import time
import sys
import pyarrow.parquet as pq
from azure.core.credentials import AccessToken
from azure.storage.blob import BlobServiceClient
from datetime import datetime
# prerequisites
# 0. Create resource group, ADFv2 instance, storage account, storage container
# 1. Download csv file of 1GB and add file to storage account
# 2. Create snapshot of file
# 3. Add 1 record to csv file and upload file again to storage account
# 4. Create new snapshot of file
# 5. Run this script
#
class CustomTokenCredential(object):
    def __init__(self, name):
       self.name = name
    def get_token(self, *scopes, **kwargs):
       access_token = self.name
       expires_on = 1000
       return AccessToken(access_token, expires_on)

@pytest.fixture()
def name(pytestconfig):
    return pytestconfig.getoption("token")

def test_adfv2_dataflows_adlsgen2_delete_piicolumns(pytestconfig):

	# https://docs.microsoft.com/en-us/samples/azure-samples/data-lake-analytics-python-auth-options/authenticating-your-python-application-against-azure-active-directory/
	# access_token = credentials.token["access_token"]
	adfv2name = pytestconfig.getoption('adfv2name')
	adlsgen2stor = pytestconfig.getoption('adlsgen2stor')
	accesskeyadls = pytestconfig.getoption('accesskeyadls')
	subscriptionid = pytestconfig.getoption('subscriptionid')
	rg = pytestconfig.getoption('rg')
	#
	# Since Azure DevOps SPN created ADFv2 instance, Azure DevOps SPN has owner rights and can execute pipelin using REST (Contributor is minimally required)
	tokenadf = pytestconfig.getoption('tokenadf')
	adfv2namepipeline = "adlsgen2-dataflows-delete-piicolumns"
	url = "https://management.azure.com/subscriptions/{}/resourceGroups/{}/providers/Microsoft.DataFactory/factories/{}/pipelines/{}/createRun?api-version=2018-06-01".format(subscriptionid, rg, adfv2name, adfv2namepipeline)
	response = requests.post(url, 
		headers={'Authorization': "Bearer " + tokenadf},
		json={
			"outputfolder": "curated"
		}
	)
	#
	assert response.status_code == 200, "test failed, pipeline not started, " + str(response.content)
	#
	runid = response.json()['runId']
	#
	count = 0
	while True:
		response = requests.get(
			"https://management.azure.com/subscriptions/{}/resourceGroups/{}/providers/Microsoft.DataFactory/factories/{}/pipelineruns/{}?api-version=2018-06-01".format(subscriptionid, rg, adfv2name, runid),
			headers={'Authorization': "Bearer " + tokenadf}
        )
		status = response.json()['status']
		if status == "InProgress" or status == "Queued":
			count += 1
			if count < 30:
				time.sleep(30) # wait 30 seconds before next status update
			else:
				# timeout
				break
		else:
			# pipeline has end state, script has finished
			print("hier2")
			break
	#
	assert count <30, "test failed, time out"
	#credential = CustomTokenCredential(tokenadls)
	credential = accesskeyadls
	storage_account_source_url = "https://" + adlsgen2stor + ".blob.core.windows.net"
	#
	client_source = BlobServiceClient(account_url=storage_account_source_url, credential=credential)
	container_source = client_source.get_container_client("curated")
	#
	blob_list = container_source.list_blobs(include=['snapshots'])
	for blob in blob_list:
		bottled_file = blob.name
	assert bottled_file == "AdultCensusIncomePIIremoved.parquet", "parquet file not found"
	#
	blob_client = client_source.get_blob_client(container="curated", blob="AdultCensusIncomePIIremoved.parquet")
	with open("AdultCensusIncomePIIremoved.parquet", "wb") as my_blob:
		download_stream = blob_client.download_blob()
		my_blob.write(download_stream.readall())
	#
	parquet_file = pq.ParquetFile('AdultCensusIncomePIIremoved.parquet')
	i = 0
	while i < parquet_file.metadata.row_group(0).num_columns:
		print(parquet_file.metadata.row_group(0).column(i).path_in_schema)
		if parquet_file.metadata.row_group(0).column(i).path_in_schema == "age":
			break
		i+=1
	# 
	assert i == parquet_file.metadata.row_group(0).num_columns, "PII age data still present"