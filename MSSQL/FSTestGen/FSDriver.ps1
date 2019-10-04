#Requires -RunAsAdministrator
#Needs elevated perms to alter FS settings for SQL Service

<#
This script will create and populate filestream objects for testing. To 
run the script, you will need the following:
 - a set of files suitable for BLOB storage (.jpg, .png, or .pdf recommended)
 - The support functions in FSTestFunctions.ps1
 - A SQL instance to test on

These functions are somewhat rough, so any errors will mean that the 
filestream objects need to be removed manually. Contact Mike Fal if you 
need assistance.
 
Update the appropriate parameters in the driver sc 
#>
#DO NOT RUN THIS TOP TO BOTTOM
#Each step should be run separately

Write-Warning "DO NOT RUN THIS TOP TO BOTTOM"
return

#Load support functions. They should reside in the same folder as this script.
. .\FSTestFunctions.ps1

#Run this ONCE for the instance
Enable-SqlFileStream -ServerInstance localhost


#Add a FS Filegroup, file, and table to target database
New-SqlFilestreamTestTable -ServerInstance localhost -DatabaseName TPCH_2F10G -FStreamPath 'E:\SQLFiles\Data\TPCH_2F10G' -TableName FSTestData

#Load FS data. It is recommended to use .jpg, png, or .pdf
$files = Get-ChildItem E:\TEMP\*.jpg
Import-SqlFilestreamData -ServerInstance localhost -DatabaseName TPCH_2F10G -TableName FSTestData -FSData $files