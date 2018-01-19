#install Module
#PowerShell 5 and elevated session.
Install-Module Rubrik -Force

#Rubrik Module Overview
Import-Module Rubrik

Get-Command -Module Rubrik
Get-Command -Module Rubrik *RubrikDatabase*

Get-Help Get-RubrikVM -ShowWindow
Get-Help New-RubrikMount -ShowWindow
Get-Help Get-RubrikRequest -ShowWindow

#Connect to Rubrik
$cred = Get-Credential
Connect-Rubrik 172.21.8.31-Credential $cred

#create credential file
$cred | Export-Clixml C:\temp\RubrikCred.xml -Force

notepad C:\temp\RubrikCred.xml

Connect-Rubrik 172.21.8.31 -Credential (Import-Clixml C:\temp\RubrikCred.xml)