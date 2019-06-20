function Get-SQLServerInstance{
    param(
        [String]$HostName,
        [String]$InstanceName = 'MSSQLSERVER'
    )
    if($InstanceName -eq 'MSSQLSERVER'){
        $SQLServerInstance = $HostName
    }else{
        $SQLServerInstance = "$HostName\$InstanceName"
    }
    return $SQLServerInstance
}
