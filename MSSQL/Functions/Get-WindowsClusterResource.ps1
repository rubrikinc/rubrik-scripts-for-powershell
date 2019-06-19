function Get-WindowsClusterResource{
    param(
        [String]$ServerInstance,
        [String]$Instance
    )
    Import-Module FailoverClusters
    Import-Module SqlServer

    $InvokeSQLCMD = @{
        Query = "SELECT TOP (1) [NodeName] FROM [master].[sys].[dm_os_cluster_nodes]"
        ServerInstance = $ServerInstance
    }
    $Results = Invoke-SQLCMD @InvokeSQLCMD      
    if ([bool]($Results.PSobject.Properties.name -match "NodeName") -eq $true){  
        $Cluster = Get-ClusterResource -Cluster $Results.NodeName | Where-Object {$_.ResourceType -like "*SQL Server*" -and $_.Name -like "*$Instance*" -and $_.Name -notlike "*Agent*"} 
        return $Cluster
    }
}