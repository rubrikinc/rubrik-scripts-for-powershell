<#
    .SYNOPSIS
        Script to start or stop Rubrik Managed volume ops
    .DESCRIPTION
        Simple script to start or stop Rubrik Managed Volume operations. Intended to be used in a Windows
        environment to "wrap around" a backup job that is being directed to a managed volume.

        To use this script, it requires a credential file to be created on the machine and under the account that
        will execute the script. To do this, log into the specified machine under the appropriate account and run:
        Get-Credential | Export-CliXml <Path to credential file location>

        The credential you will use is the *Rubrik credential*, not the windows credential. This file will be used by the
        script to connect to Rubrik and run the Managed Volume scripts.

        Once you've set the credentail file path in the script, also enter the IP address for the Rubrik cluster.

    .PARAMETER mvname
        Managed Volume name   
    .PARAMETER Start
        Switch to start Managed Volume snapshot, mutually exclusiave of Stop
    .PARAMETER Stop
        Switch to start Managed Volume snapshot, mutually exclusiave of Stop
    .EXAMPLE
        .\SQLMVOps -mvname FOO -Start

        Start a snapshot for Managed Volume FOO

    .NOTES  
        Created:    2018-10-28
        Author:     Mike Fal

#>
param([Parameter(Mandatory=$true)]
      [string]$mvname
     ,[Switch]$Start
     ,[Switch]$Stop)

$RubrikCluster = '0.0.0.0'
$CredFile = 'E:\SQLOla\rubrikcred_ola.xml'

Connect-Rubrik -Server $RubrikCluster -Credential (Import-Clixml $CredFile) | Out-Null

if($Start){Get-RubrikManagedVolume -Name $mvname | Start-RubrikManagedVolumeSnapshot}
if($stop){Get-RubrikManagedVolume -Name $mvname | Stop-RubrikManagedVolumeSnapshot}