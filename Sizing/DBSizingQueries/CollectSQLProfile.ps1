<#
.SYNOPSIS
    MSSQL Database Sizing Scripts for Rubrik
    
.EXAMPLE
    To run the script use the below command with the SQLInstance parameter. Then provide that parameter with a comma separated list of SQL Servers. The script will use Windows Authentication to collect data. 
    PS C:\> .\CollectSQLProfile.ps1 -SQLInstance SQL1, SQL2, SQL3, SQL4\Instance1

.EXAMPLE
    If you need to use SQL Authentication instead of Windows Authentication, then include the Credential parameter and provide it with a user name. You will be prompted for a password. 
    PS C:\> .\CollectSQLProfile.ps1 -SQLInstance SQL1, SQL2, SQL3, SQL4\Instance1 -Credential sa

.EXAMPLE
    Instead of giving a comma separated list of sql servers, you can use the InstancesFile parameter. Provide a file that contains a list of sql server instances. Each instance should be on a separate line.
    PS C:\> .\CollectSQLProfile.ps1 -InstancesFile SQLInstances.txt
.NOTES
    Name:       MSSQL Database Sizing Scripts for Rubrik
    Author:     Mike Fal, Chris Lumnah    
#>
[cmdletbinding()]
param(
    [Parameter(ParameterSetName='List Of Instances')]
    [string[]] $SQLInstance,
    [Parameter(ParameterSetName='File Of Instances')]
    [String] $InstancesFile,
    [string] $OutPath = [Environment]::GetFolderPath("MyDocuments"),
    [string] $QueryPath = '.\',
    [Switch] $Anonymize,
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty
)
BEGIN{
    if(Get-Module -ListAvailable SqlServer){Import-Module SqlServer}
    else{Import-Module SQLPS -DisableNameChecking}

    $queries = Get-ChildItem $QueryPath -Filter "*.sql"
    $queries | ForEach-Object {$_ | Add-Member -MemberType NoteProperty -Name FileName -Value "$($_.Name.Replace('.sql',''))-$(Get-Date -Format 'yyyyMMddHHmm').csv"}
    $header = $true
    if (![string]::IsNullOrEmpty($InstancesFile)){
        if (Test-Path $InstancesFile){
            $SQLInstance = Get-Content -Path $InstancesFile
        }
    }
}
PROCESS{
    foreach($i in $SQLInstance){
        $svr = new-object "Microsoft.SqlServer.Management.Smo.Server" $i;
        if (![string]::IsNullOrEmpty($Credential.UserName)){
            $svr.ConnectionContext.LoginSecure = $false
            $svr.ConnectionContext.set_Login($Credential.UserName)
            $svr.ConnectionContext.set_SecurePassword($Credential.Password)
        }
        $svr.ConnectionContext.connectTimeout = 4
        if ([string]::IsNullOrEmpty($svr.Edition)){
            Write-Warning "!!!!!!! Can not connect to the SQL Service on: $i !!!!!!!"
            $i | Out-File -FilePath (Join-Path -Path $OutPath -ChildPath "SizingQuery-ServerWeCouldNotConnectTo.txt") -Append
            continue
        }
        if($Anonymize){
            $serverid = [guid]::NewGuid()
        }
        foreach($q in $queries){
            $sql = (Get-Content $q) -join "`n"
            if($Anonymize){$sql = $sql.Replace("@@SERVERNAME","'$serverid'")}
            $OutFile = Join-Path -Path $OutPath -ChildPath $q.filename

            Write-Verbose "Collecting data from $i"
            $output = Invoke-SqlCmd -ServerInstance "$i" -Database TempDB -Query "$sql" -Credential $Credential

            if($header -eq $true){
                $output | ConvertTo-Csv -Delimiter '|' -NoTypeInformation | Out-File $OutFile -Append
            }
            else{
                $output | ConvertTo-Csv -Delimiter '|' -NoTypeInformation | Select-Object -skip 1 |Out-File $OutFile -Append
            }
            $output = ""
        }
        $header = $false
    }
}
END{}