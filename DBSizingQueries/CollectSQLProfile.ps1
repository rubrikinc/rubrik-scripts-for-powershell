[cmdletbinding()]
param(
    [string[]] $SQLInstance
    ,[string] $OutPath = [Environment]::GetFolderPath("MyDocuments")
    ,[string] $QueryPath = '.\'
    ,[Switch] $Anonymize
    ,[string] $SqlUser
    ,[string] $SqlPassword
)
BEGIN{
    if(Get-Module -ListAvailable SqlServer){Import-Module SqlServer}
    else{Import-Module SQLPS -DisableNameChecking}

    $queries = Get-ChildItem $QueryPath -Filter "*.sql"
    $queries | ForEach-Object {$_ | Add-Member -MemberType NoteProperty -Name FileName -Value "$($_.Name.Replace('.sql',''))-$(Get-Date -Format 'yyyyMMddHHmm').csv"}
    $header = $true
}

PROCESS{
foreach($i in $SQLInstance){
    if($Anonymize){
        $serverid = [guid]::NewGuid()
    }
    foreach($q in $queries){

        $sql = (Get-Content $q) -join "`n"
        if($Anonymize){$sql = $sql.Replace("@@SERVERNAME","'$serverid'")}
        $OutFile = Join-Path -Path $OutPath -ChildPath $q.filename

        if($SqlUser -and $SqlPassword){
            $output = Invoke-SqlCmd -ServerInstance "$i" -Database TempDB -Query "$sql" -Username $SqlUser -Password $SqlPassword 
        } else {
            $output = Invoke-SqlCmd -ServerInstance "$i" -Database TempDB -Query "$sql" 
        }

        if($header -eq $true){
            $output | ConvertTo-Csv -Delimiter '|' -NoTypeInformation | Out-File $OutFile -Append
            }else {
            $output | ConvertTo-Csv -Delimiter '|' -NoTypeInformation | Select-Object -skip 1 |Out-File $OutFile -Append
            }
        }
        $header = $false
    }
}

END{}