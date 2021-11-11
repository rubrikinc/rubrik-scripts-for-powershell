<# 
    .SYNOPSIS 
    Run diskspd tests against a list of servers from a management box. 
    
    .DESCRIPTION
    Run diskspd tests against a list of servers from a management box. This script requires that Powershell Remoting is configured to be able to connect to your list of servers. If that is not configured properly, 
    this script will fail when attempting to run remotely. 

    This script will check to see if the target box to run the test on it, has diskspd installed already. If it does not, it will download it and place it into C:\DISKSPD unless otherwise directed.
    Once DISKSPD is installed it will run a battery of tests against volumes on the Windows box. The tests are designed to test storage response based on the Rubrik backup and restore workload. This meand we 
    will test the storage using a 1MB block size and do sequential reads and writes. 

    The battery of tests will include both read and write tests at a series of queue depths. This script executes numerous DiskSpd tests and saves the output to an XML file. The XML file is then loaded and the
    appropriate data pulled out into a CSV file for future analysis.
    
    Please notify your storage administrator that you plan to execute 
    this test. Do not run this script on any environment without the 
    express understanding that you can cause performance and/or availability 
    issues with production environments from misuse of any
    storage benchmarking tool and script, including this one.
    
    You should run this with administrative privileges to create the workload file 
    properly.
    
    - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
    Obligatory Disclaimer
    THE SCRIPT AND PARSER IS PROVIDED �AS IS� AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE 
    INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY 
    SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA 
    OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION 
    WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
    - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 

    Thanks to David Klee at Heraflux http://www.heraflux.com. He wrote the original version of this script, and I took portions of his code to build this. 
    
    .PARAMETER ComputerName
    Provide a comma separated list of server names

    .PARAMETER diskspdPath
    Path to where diskspd should be installed on the target box

    .PARAMETER OutPath
    Output folder where results should be placed. 

    .PARAMETER TestDuration
    How long should the test run for in seconds
        
    .PARAMETER DataFileSize
    Size of the file that will be used in the workload

    .PARAMETER BlockSize
    Change the test block size (in KB "K" or MB "M") according to your application workload profile 

    .PARAMETER Threads
    Threads to be used for the workload. Rubrik uses 8 threads to read and write to a file. We default this to 8, but you should change this if you want to see what to expect if you change this in Rubrik

    .PARAMETER ThrottleLimit
    Will limit the number of concurrent diskspd tests that can be run at one time. We default this to 2, but if your SAN Admin says it is ok and your infrastructure could handle more, increase this value to do more concurrent diskspd tests

    .EXAMPLE
    Run against the local machine. This will run a battery of tests against all volumes on the local machine. Output will be captured in the c:\diskspd folder and then moved to the c:\scripts for analysis
    C:\scripts>.\Run-diskspdTests.ps1

    .EXAMPLE
    Run against a single remote machine. Run a battery of tests against all volumes on the remove machine. Output will be captured in the c:\diskspd folder on the remote machine and then moved to the c:\scripts 
    on the lcoal machine for analysis
    C:\scripts>.\Run-diskspdTests.ps1 -ComputerName Server01 

    .EXAMPLE
    Run against multiple remote machines. Run a battery of tests against all volumes on the remove machine. In this example we will run each test 
    - Against Server01, Server02, Server03, Server04
    - For 60 seconds 
    - with a filesize 10GB
    - a BlockSize of 1MB
    - a ThrottleLimit of 2. This will cause the script to run the battery against 2 machines concurrently. 
    - with 8 threads
    Output will be captured in the c:\diskspd folder on the remote machine and then moved to the c:\scripts on the lcoal machine for analysis
    C:\scripts>.\Run-diskspdTests.ps1 -ComputerName Server01, Server02, Server03, Server04 -ThrottleLimit 2 -TestDuration 60 -DataFileSize 10G -Threads 8 -BlockSize 1M
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,Position=0)]
    [String[]]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory=$false,Position=1)]
    $diskspdPath = 'C:\DISKSPD',

    [Parameter(Mandatory=$false,Position=2)]
    $OutPath = "C:\DISKSPD\",

    [Parameter(Mandatory=$false,Position=3)]
    $TestDuration = 60,

    [Parameter(Mandatory=$false,Position=4)]
    $DataFileSize = "5G",

    [Parameter(Mandatory=$false,Position=5)]
    $ReadBlockSize = "1M",
    
    [Parameter(Mandatory=$false,Position=6)]
    $WriteBlockSize = "4M",

    [Parameter(Mandatory=$false,Position=7)]
    $Threads = 16,

    [Parameter(Mandatory=$false,Position=8)]
    $ThrottleLimit = 2
)
#region Variables
$EntropySize = $DataFileSize
#endregion

function Start-DiskspdTest{
    param(
        $ComputerName,
        $TestDuration,
        $diskspdPath,
        $DataFileSize,
        $Threads,
        $ReadBlockSize,
        $WriteBlockSize,
        $EntropySize,
        $OutPath
    )
    
    $IODepths = @(1,2,4,8,16,32,64,128) #,256,512)
    $IOTypes = @("read","write")
    $env:COMPUTERNAME
    #region Determine number of tests to run
    # Get a list of volumes to test
    $Volumes = Get-CimInstance -ClassName Win32_Volume -Filter "DriveType='3'" -ComputerName $ComputerName | Where-Object {$_.Label -ne "System Reserved" -and $_.Name -notlike "*temp*"}
    Write-Host "Number of Volumes to be tested: $($Volumes.PSComputerName.Count)"
    $TestCount = $IODepths.Count * $IOTypes.Count * $Volumes.PSComputerName.Count
    
    Write-Host Number of tests to be executed: $TestCount
    Write-Host "Approximate time to complete test:" ([System.Math]::Ceiling($TestCount * $TestDuration / 60)) "minute(s)"
    #endregion

    #region Make sure that DISKSPD is on the target computer
    if (!(Test-Path -Path "$($diskspdPath)\x86\diskspd.exe")){
        $client = new-object System.Net.WebClient
        if (!(Test-Path -Path "C:\Temp")){New-Item -Path "C:\Temp" -ItemType Directory}
        $client.DownloadFile("https://github.com/microsoft/diskspd/releases/download/v2.0.21a/DiskSpd.zip","C:\temp\DiskSpd-2.0.21a.zip")
        Expand-Archive -LiteralPath c:\temp\DiskSpd-2.0.21a.zip -DestinationPath $diskspdPath -Force
    }
    #endregion

    #region  Run DISKSPD Tests
    Write-Host "DiskSpd test sweep - Now beginning"
    $TestNumber = 1
    $p = New-Object System.Diagnostics.Process
    $diskspdExe = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($diskspdPath)
    $p.StartInfo.FileName = "$diskspdExe\x86\diskspd.exe"
    $p.StartInfo.RedirectStandardError = $true
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.UseShellExecute = $false

    foreach ($Volume in $Volumes){
        foreach ($IOType in $IOTypes){
            switch ($IOType){
                "read" {$WriteTest = 0}
                "write" {$WriteTest = 100}
            }
            foreach($IODepth in $IODepths){
                #region timestamp output file
                $FileName = "diskspd_results_"+(Get-Date -format '_yyyyMMdd_HHmmss') + ".rbk"
                $OutFile = Join-Path -Path $OutPath -childpath $FileName
                #endregion

                Write-Progress -Activity "Executing DiskSpd Tests..." -Status "Executing Test $TestNumber of $TestCount" -PercentComplete ( ($TestNumber / ($TestCount)) * 100 )
                switch ($IOType){
                    "read" {
                        $WriteTest = 0
                        $arguments = "-c$($DataFileSize) -w$($WriteTest) -t$($Threads) -d$($TestDuration) -o$($IODepth) -b$($ReadBlockSize) -Z$($EntropySize) -W20 -Rxml -si -L $($Volume.Name)iotest.dat"
                    }
                    "write" {
                        $WriteTest = 100
                        $arguments = "-c$($DataFileSize) -w$($WriteTest) -t$($Threads) -d$($TestDuration) -o$($IODepth) -b$($WriteBlockSize) -Z$($EntropySize) -W20 -Rxml -si -L $($Volume.Name)iotest.dat"
                    }
                }

                # Write-Output "diskspd.exe  $arguments" 

                $p.StartInfo.Arguments = $arguments
                $p.Start() | Out-Null
                $Output = $p.StandardOutput.ReadToEnd()
                $TestNumber = $TestNumber + 1
                $Output | Out-File $outfile
                $p.WaitForExit()
                Remove-Item -Path "$($Volume.Name)iotest.dat"
            }
        }
    }
}

 

foreach ($Computer in $ComputerName){
    if ($Computer -ne $env:COMPUTERNAME){
        $InvokeCommand = @{
            ComputerName = $Computer
            ScriptBlock = ${Function:Start-DiskspdTest}
            ArgumentList = $Computer, $TestDuration,$diskspdPath, $DataFileSize, $Threads, $ReadBlockSize, $WriteBlockSize, $EntropySize, $OutPath
            ThrottleLimit = $ThrottleLimit
        }
    }else{
        $InvokeCommand = @{
            ScriptBlock = ${Function:Start-DiskspdTest}
            ArgumentList = $Computer,$TestDuration,$diskspdPath, $DataFileSize, $Threads, $ReadBlockSize, $WriteBlockSize, $EntropySize, $OutPath
        }
    }
    Invoke-Command @InvokeCommand
}
#region Retrieve output files and bring them locally for analysis
if ($ComputerName -eq $env:COMPUTERNAME){
    Copy-Item -Path "$($diskspdPath)\*.rbk" -Destination ".\"
    Remove-Item -Path "$($diskspdPath)\*.rbk"
}else{
    foreach ($Computer in $ComputerName){
        if ((Test-Path -Path "\\$($Computer)\$($diskspdPath)\*.rbk".Replace(":","$"))){
            Copy-Item -Path "\\$($Computer)\$($diskspdPath)\*.rbk".Replace(":","$") -Destination ".\"
            Remove-Item -Path "\\$($Computer)\$($diskspdPath)\*.rbk".Replace(":","$")
        }else{
            Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
            Write-Host "Could not copy files from \\$($Computer)\$($diskspdPath)\*.rbk".Replace(":","$") -ForegroundColor White
            Write-Host "Look in " -ForegroundColor White -NoNewline
            Write-Host "$($diskspdPath) " -ForegroundColor Red -NoNewline 
            Write-Host "on " -ForegroundColor White -NoNewLine
            Write-Host "$($Computer) " -ForegroundColor Red  -NoNewline
            Write-Host "to see if the files exist. If they do, then check to see if your" -ForegroundColor White
            Write-Host "firewall is preventing the copying of files across the network." -ForegroundColor White
            Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
        }
    }
}
#endregion