function Get-SQLDatabaseDefaultLocations{
    #Code is based on snippet provied by Steve Bonham of LFG
    param(
        [Parameter(Mandatory=$true)]
        [string]$Server
    )
    Import-Module sqlserver  
    $SMOServer = new-object ('Microsoft.SqlServer.Management.Smo.Server') $Server 

    # Get the Default File Locations 
    $DatabaseDefaultLocations = New-Object PSObject
    Add-Member -InputObject $DatabaseDefaultLocations -MemberType NoteProperty -Name Data -Value $SMOServer.Settings.DefaultFile 
    Add-Member -InputObject $DatabaseDefaultLocations -MemberType NoteProperty -Name Log -Value $SMOServer.Settings.DefaultLog 
  
    if ($DatabaseDefaultLocations.Data.Length -eq 0){$DatabaseDefaultLocations.Data = $SMOServer.Information.MasterDBPath} 
    if ($DatabaseDefaultLocations.Log.Length -eq 0){$DatabaseDefaultLocations.Log = $SMOServer.Information.MasterDBLogPath} 
    return $DatabaseDefaultLocations
}