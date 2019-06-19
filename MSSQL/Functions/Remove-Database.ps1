function Remove-Database{
    param(
        [String]$DatabaseName,
        [String]$ServerInstance
    )
    
    $Query = "SELECT state_desc FROM sys.databases WHERE name = '" + $DatabaseName + "'" 
    $Results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $Query

    if ([bool]($Results.PSobject.Properties.name -match "state_desc") -eq $true){
        if ($Results.state_desc -eq 'ONLINE'){
            Write-Host "Setting $($DatabaseName) to SINGLE_USER"
            Write-Host "Dropping $($DatabaseName)"
            $Query = "ALTER DATABASE [" + $DatabaseName + "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; `nDROP DATABASE [" + $DatabaseName + "]"
            $Results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $Query
        }
        else {
            Write-Host "Dropping $($DatabaseName)"
            $Query = "DROP DATABASE [" + $DatabaseName + "]"
            $Results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $Query -Database master
        }
    }
}