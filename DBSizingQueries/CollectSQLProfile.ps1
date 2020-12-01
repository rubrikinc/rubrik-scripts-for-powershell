[cmdletbinding()]
param(
    [string[]] $SQLInstance 
    ,[string] $OutPath = [Environment]::GetFolderPath("MyDocuments")
    ,[string] $QueryPath = '.\'
    ,[Switch] $Anonymize
    ,[string] $SqlUser
    ,[string] $SqlPassword
    ,[String] $InstanceCSVFile
)
BEGIN{
    if(Get-Module -ListAvailable SqlServer){Import-Module SqlServer}
    else{Import-Module SQLPS -DisableNameChecking}

    $queries = Get-ChildItem $QueryPath -Filter "*.sql"
    $queries | ForEach-Object {$_ | Add-Member -MemberType NoteProperty -Name FileName -Value "$($_.Name.Replace('.sql',''))-$(Get-Date -Format 'yyyyMMddHHmm').csv"}
    $header = $true

    # If specified, the host/instance entries in the csv file will be appended to the $SQLInstance array of String objects
    #
    # Format of CSV file:
    #
    # host,instance
    # myhost,ZeSQLInstance
    if (Test-Path $InstanceCSVFile -PathType leaf)
    {
        $instObjArray = Import-CSV -path $InstanceCSVFile

        $instObjArray | ForEach-Object {
            [String] $tmpInstance

            if($_.instance -eq 'default')
            {
                $tmpInstance = $_.host
            }
            else
            {
                $tmpInstance = ("[0]\[1]" -f $_.host, $_.instance)
            }

            $SQLInstance += $tmpInstance
        }
    }
}

PROCESS
{
    foreach($i in $SQLInstance)
    {
        $svr = new-object "Microsoft.SqlServer.Management.Smo.Server" $i;
        $svr.ConnectionContext.connectTimeout = 4
        if ($svr.Edition -eq $null)
        {
            Write-Warning "!!!!!!! Can not connect to the SQL Service on: $i !!!!!!!"
            $i | Out-File -FilePath (Join-Path -Path $OutPath -ChildPath "SizingQuery-ServerWeCouldNotConnectTo.txt") -Append
            continue
        }
        if($Anonymize)
        {
            $serverid = [guid]::NewGuid()
        }
        foreach($q in $queries)
        {
            $sql = (Get-Content $q) -join "`n"
            if($Anonymize){$sql = $sql.Replace("@@SERVERNAME","'$serverid'")}
            $OutFile = Join-Path -Path $OutPath -ChildPath $q.filename

            Write-Verbose "Collecting data from $i"
            if($SqlUser -and $SqlPassword)
            {
                $output = Invoke-SqlCmd -ServerInstance "$i" -Database TempDB -Query "$sql" -Username $SqlUser -Password $SqlPassword
            }
            else
            {
                $output = Invoke-SqlCmd -ServerInstance "$i" -Database TempDB -Query "$sql"
            }

            if($header -eq $true)
            {
                $output | ConvertTo-Csv -Delimiter '|' -NoTypeInformation | Out-File $OutFile -Append
            }
            else
            {
                $output | ConvertTo-Csv -Delimiter '|' -NoTypeInformation | Select-Object -skip 1 |Out-File $OutFile -Append
            }
            $output = ""
        }
        $header = $false
    }
}

END{}