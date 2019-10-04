Contributions via GitHub pull requests are gladly accepted from their original author. Along with any pull requests, please state that the contribution is your original work and that you license the work to the project under the project's open source license. Whether or not you state this explicitly, by submitting any copyrighted material via pull request, email, or other means you agree to license the material under the project's open source license and warrant that you have the legal authority to do so.

When Adding a new powershell script to this repository, the following must be present at the top of the script:

```
<#
.SYNOPSIS
A simple summary of the purpose of this script

.DESCRIPTION
A simple description outlining the specific actions of this script

.PARAMETER <Parameter Name - Repeat for each parameter>
A description of the parameter e.g. Hostname of the SQL Server

.EXAMPLE
A example of the scripts usage e.g. :
    $RubrikServer = "172.21.8.51"
    $RubrikCredential = (Get-Credential -Message 'Please enter your Rubrik credentials')
    Connect-Rubrik -Server $RubrikServer -Credential $RubrikCredential
    .\copy-LMDatabaseFiles.ps1 -HostName sql1.domain.com `
        -Instance mssqlserver `
        -RubrikServer 172.21.8.51 `
        -Destination "C:\temp\"

.NOTES
This section is regarding the author and tracking for the creation of the script:
Name:               Name of the Script
Created:            Date Created or Added to Github
Author:             Name of the Author
CDM:                Version of CDM Run Against
#>
```