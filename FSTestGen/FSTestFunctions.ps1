
if(Get-Module -ListAvailable SqlServer){Import-Module SqlServer}
    else{Import-Module SQLPS -DisableNameChecking}

function Enable-SqlFileStream{
param(
        $ServerInstance
)

    $ComputerName = ($ServerInstance.Split('\'))[0]
    $instance = ($ServerInstance.Split('\'))[1]
    if($instance -eq $null){$instance = 'MSSQLSERVER'}

    $smosrv = New-Object  Microsoft.SqlServer.Management.Smo.Server $ServerInstance


    $wmi=Get-WmiObject -ComputerName $ComputerName -namespace "root\Microsoft\SqlServer\ComputerManagement$($smosrv.VersionMajor)" -class FILESTREAMSettings | where {$_.InstanceName -eq $instance}
    $wmi.EnableFILESTREAM(2,$instance)

    $smosrv.Configuration.FilestreamAccessLevel.ConfigValue = [Microsoft.SqlServer.Management.Smo.FileStreamLevel]::TSqlAccess
    $smosrv.Alter()
    Write-Warning "Restart $ServerInstance to complete the change"
}

function New-SqlFilestreamTestTable{
    param($ServerInstance,
          $DatabaseName,
          $FStreamPath,
          $TableName)

$sql = "
IF(SELECT value_in_use FROM sys.configurations WHERE name = 'filestream access level') = 0
BEGIN
    exec sp_configure 'filestream access level',1
    reconfigure
END

ALTER DATABASE $DatabaseName
ADD FILEGROUP [FSTTEST] CONTAINS FILESTREAM
GO

ALTER DATABASE $DatabaseName
ADD FILE (name=FSTEST,FILENAME='$FStreamPath\FSTEST')
to FILEGROUP [FSTTEST]
GO

CREATE TABLE FSTEST_Data
(InsertDate DATETIME NOT NULL
,FSGUID UNIQUEIDENTIFIER ROWGUIDCOL NOT NULL UNIQUE
,FSDATA varbinary(max) FILESTREAM
,INDEX CI_FSTest_Data CLUSTERED (InsertDate)
)"

Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $DatabaseName -Query $sql

}

function Import-SqlFilestreamData{
    param(
        $ServerInstance,
        $DatabaseName,
        [System.IO.FileInfo[]]$FSData,
        $TableName
    )

foreach($file in $FSData){
    $sql = "INSERT INTO FSTEST_Data
    SELECT GETDATE(), NEWID(),convert(varbinary(max),bulkcolumn)
    from openrowset(BULK '$($file.FullName)' ,SINGLE_BLOB) as bulkdata;"

    Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $DatabaseName -Query $sql

    }
}