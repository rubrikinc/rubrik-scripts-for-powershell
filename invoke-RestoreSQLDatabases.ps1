<#
    .SYNOPSIS
        Script restore given databases from a SQL Server instance
    .DESCRIPTION
        Script restore given databases from a SQL Server instance. It will restore or export a database depending on the parameters        
    .PARAMETER databases
        Mandatory parameter, can be a array of database names    
    .PARAMETER SourceServerInstance
        SQL Server Instance name where the given database is hosted, this is the Source SQL Server instance. If default instance, then just use the server name, if a named instance, use
        Server\Instance
    .PARAMETER TargetServerInstance
        SQL Server Instance name where the databases will be restored, this is the Target SQL Server instance. If default instance, then just use the server name, if a named instance, use
        Server\Instance
    .PARAMETER TargetDataFilePath
        Path where the data file should be restored, if not informed, Rubrik will use the same location as Source instance
        ex. D:\Data
    .PARAMETER TargetLogFilePath
        Path where the log file database should be restored, if not informed, Rubrik will use the same location as Source instance
        ex. D:\Log        
    .PARAMETER Overwrite
        optional parameter, should be used when the database already exists on Target server
    .PARAMETER Restore
        optional parameter, should be used if you want to restore the database at the source server, in this case it is not necessary to inform the target server, Rubrik will use the Source 
        Server as target.
    .PARAMETER LatestRecoveryPoint
        optional parameter, should be used if you want to restore the latest recovery point for given databases.
        If this parameter was not informed, you have to inform the ReveryDateTime parameter
    .PARAMETER RecoveryDateTime
        optional parameter, should be used if you want to restore an specif point in time,
        this parameter has precedence in relation to the parameter LatestRecoveryPoint, so do not use this parameter toggeter with parameter LatestRecoveryPoint
    .EXAMPLE
        Example of how to run the script

        $databases = "dbDemo01","dbDemo02"
        $SourceServerInstance = "MF-SQLXP"
        $TargetServerInstance = "MF-SQL17-test"
        $RecoveryDateTime = $(Get-Date).AddMinutes(-5)
        $TargetDataFilePath = "C:\Data"
        $TargetLogFilePath = "C:\Log"
        
        Exporting databases to an specific driver and using an specific point in time
        .\invoke-RestoreSQLDatabases.ps1 -databases $databases `
                -SourceServerInstance $SourceServerInstance `
                -TargetServerInstance $TargetServerInstance `
                -RecoveryDateTime $RecoveryDateTime `
                -TargetDataFilePath $TargetDataFilePath `
                -TargetLogFilePath $TargetLogFilePath `
                -Confirm:$false `
                -Verbose 

        Recovering databases using the latest recovey point
        .\invoke-RestoreSQLDatabases.ps1 -databases $databases `
                -SourceServerInstance $SourceServerInstance `
                -LatestRecoveryPoint `
                -Restore `
                -Confirm:$false `
                -Verbose 
    .LINK
        None
    .NOTES
        Name:       Restore or Export databases from given instance.
        Created:    2019-04-18
        Author:     Marcelo Fernandes
#>
#requires -Modules Rubrik
[cmdletbinding(SupportsShouldProcess=$true,ConfirmImpact='High')]

param( [Parameter(Mandatory=$true)]
         [string[]]$databases
        ,[Parameter(Mandatory=$true)]
         [String]$SourceServerInstance
        ,[String]$TargetServerInstance
        ,[string]$TargetDataFilePath
        ,[string]$TargetLogFilePath
        ,[Switch]$Overwrite
        ,[Switch]$Restore
        ,[Switch]$LatestRecoveryPoint
        ,[ValidateScript({get-date $_ })] 
         [datetime]$RecoveryDateTime        
        )

BEGIN{

    if($SourceServerInstance -contains '\'){
        $srcHostName = ($SourceServerInstance -split '\')[0]
        $srcInstanceName = ($SourceServerInstance -split '\')[1]
    } else {
        $srcHostName = $SourceServerInstance
        $srcInstanceName = 'MSSQLSERVER'
    }

    if($TargetServerInstance -contains '\'){
        $tgtHostName = ($TargetServerInstance -split '\')[0]
        $tgtInstanceName = ($TargetServerInstance -split '\')[1]
    } else {
        $tgtHostName = $TargetServerInstance
        $tgtInstanceName = 'MSSQLSERVER'
    }
    $target = Get-RubrikSQLInstance -Name $tgtInstanceName -ServerInstance $tgtHostName

    #Validations

    #If missing parameter TargetServerInstance, the parameter -Restore is requited to replace the DB at the SourceServerInstance
    if(!$TargetServerInstance -and !$Restore){
       write-warning -message "You have to inform the parameters: -TargetServerInstance or -Restore"
       break
    }
    #If missing parameter RecoveryDateTime, the parameter -LatestRecoveryPoint is required to restore the lastes recovery point
    if(!$RecoveryDateTime -and !$LatestRecoveryPoint){
       write-warning -message "You have to inform the parameters: -RecoveryDateTime or -LatestRecoveryPoint"
       break
    }

}

PROCESS{
    foreach($db in $databases) {
        if($PSCmdlet.ShouldProcess($db)){

            $sourcedb = Get-RubrikDatabase -Hostname $srcHostName -Instance $srcInstanceName -Database $db
            #for AG databases
            if (!$sourcedb)
            {
                $sourcedb = Get-RubrikDatabase -Name $db -Hostname $srcHostName
            }
            $sourcedb = $sourcedb | Get-RubrikDatabase | Where-Object {$_.isrelic -ne 'TRUE' -and $_.isLiveMount -ne 'TRUE'}

            if(!$sourcedb){Write-Host "The database [$db] cannot be found." -ForegroundColor Yellow}
            else{
                if($RecoveryDateTime){$srcRecoveryDateTime = $RecoveryDateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }else{$srcRecoveryDateTime = (Get-Date $sourcedb.latestRecoveryPoint)}

                if (!$TargetDataFilePath -or !$TargetLogFilePath){
                    Write-Verbose "Getting file path from source DB"
                    try{$sourcefiles = $sourcefiles = Get-RubrikDatabaseFiles -Id $sourcedb.id -RecoveryDateTime $srcRecoveryDateTime |Select-Object LogicalName,@{n='exportPath';e={$_.OriginalPath}},@{n='newFileName';e={$_.OriginalName}}
                    }catch{Write-Warning -Message "$srcRecoveryDateTime is not recoverable";continue}
                }else{
                    Write-Verbose "Using file path [$TargetDataFilePath] and [$TargetLogFilePath] for [$db]"                
                    try{$sourcefiles = Get-RubrikDatabaseFiles -Id $sourcedb.id -RecoveryDateTime $srcRecoveryDateTime |Select-Object LogicalName,@{n='exportPath';e={if($_.fileType -eq "Data"){$TargetDataFilePath}else{$TargetLogFilePath}}},@{n='newFileName';e={$_.OriginalName}}
                    }catch{Write-Warning -Message "$srcRecoveryDateTime is not recoverable"; continue}
                }

                if($Restore){
                    Write-Verbose "Restoring database [$db] from [$srcHostName\$srcInstanceName] to [$srcHostName\$srcInstanceName]."                
                    $Result = Restore-RubrikDatabase -id $sourcedb.id -RecoveryDateTime $srcRecoveryDateTime -FinishRecovery -Confirm:$false
                }else{
                    Write-Verbose "Exporting database [$db] from [$srcHostName\$srcInstanceName] to [$tgtHostName\$tgtInstanceName]."
                    try{
                    $Result = Export-RubrikDatabase -Id $sourcedb.id `
                            -TargetInstanceId $target.id `
                            -TargetDatabaseName $sourcedb.name `
                            -recoveryDateTime $srcRecoveryDateTime `
                            -FinishRecovery `
                            -Overwrite:$Overwrite `
                            -TargetFilePaths $sourcefiles `
                            -Confirm:$false
                    }catch{$_}
                }
            }      
        }
    }
}