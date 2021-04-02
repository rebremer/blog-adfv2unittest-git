import pytest
import os
import requests
import adal
from msrestazure.azure_active_directory import AADTokenCredentials
import time
import sys
import pyodbc
import struct

# prerequisites
# 0. Create resource group, ADFv2 instance, storage account, storage container
# 1. Download csv file of 1GB and add file to storage account
# 2. Create snapshot of file
# 3. Add 1 record to csv file and upload file again to storage account
# 4. Create new snapshot of file
# 5. Run this script
#
@pytest.fixture()
def name(pytestconfig):
    return pytestconfig.getoption("token")

def test_run_pipeline(pytestconfig):

	# https://docs.microsoft.com/en-us/samples/azure-samples/data-lake-analytics-python-auth-options/authenticating-your-python-application-against-azure-active-directory/
	# access_token = credentials.token["access_token"]
	tokendb = pytestconfig.getoption('tokendb')
	adfv2name = pytestconfig.getoption('adfv2name')
	sqlserver = pytestconfig.getoption('sqlserver') + '.database.windows.net'
	sqldatabase = pytestconfig.getoption('sqldatabase')
	sqllogin = pytestconfig.getoption('sqllogin')
	sqlpassword = pytestconfig.getoption('sqlpassword')
	azuredevopsspndbadmin = pytestconfig.getoption('azuredevopsspndbadmin')
	subscriptionid = pytestconfig.getoption('subscriptionid')
	rg = pytestconfig.getoption('rg')
	#
	# Since Azure DevOps SPN created ADFv2 instance, Azure DevOps SPN has owner rights and can execute pipelin using REST (Contributor is minimally required)
	tokenadf = pytestconfig.getoption('tokenadf')
	adfv2namepipeline = "sqldb-dataflows-remove-nullvalues"
	url = "https://management.azure.com/subscriptions/{}/resourceGroups/{}/providers/Microsoft.DataFactory/factories/{}/pipelines/{}/createRun?api-version=2018-06-01".format(subscriptionid, rg, adfv2name, adfv2namepipeline)
	response = requests.post(url, 
		headers={'Authorization': "Bearer " + tokenadf},
		json={}
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
	#
	if azuredevopsspndbadmin == 1:
		# Azure DevOPs is SQL Azure AD admin and ADFv2 MI shall be added to database as user
		accessToken = bytes(tokendb, 'utf-8')
		exptoken = b""
		for i in accessToken:
			exptoken += bytes({i})
			exptoken += bytes(1)
		tokenstruct = struct.pack("=i", len(exptoken)) + exptoken
		connstr = 'DRIVER={ODBC Driver 17 for SQL Server};SERVER='+sqlserver+';DATABASE='+sqldatabase
		conn = pyodbc.connect(connstr, attrs_before = { 1256:tokenstruct })
		cursor = conn.cursor()
		#
		create_user ="CREATE USER [" + adfv2name + "] FROM EXTERNAL PROVIDER;"
		cursor.execute(create_user)
		add_role = "EXEC sp_addrolemember [db_owner], [" + adfv2name + "];"
		cursor.execute(add_role)	
	else:
		# ADFv2 MI is Azure AD admin, SQL local user shall be used to query results database from Azure DevOps
		connstr = 'DRIVER={ODBC Driver 17 for SQL Server};SERVER='+sqlserver+';UID='+sqllogin+';PWD='+sqlpassword+';DATABASE='+sqldatabase
		conn = pyodbc.connect(connstr)
		cursor = conn.cursor()
	cursor.execute("SELECT count(*) FROM Sales.OrdersAggregated WHERE Comments != 'test123'")
	row = cursor.fetchall()
	value = [record[0] for record in row]
	#
	assert value[0] == 0,"test failed, table does not contain number of records"