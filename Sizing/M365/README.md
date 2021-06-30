# M365 Sizing Script

This document contains instructions on how to use the Rubrik M365 Protection Sizing PowerShell Script



## Requirements

* Requires `PowerShell >= 5.1` for PowerShell Gallery.
* Requires user with MS Graph access.



## Installation

1. Install the `Microsoft.Graph.Authenication and Microsoft.Graph.Reports` PowerShell module from the PowerShell Gallery
    ```
    Install-Module Microsoft.Graph.Authenication, Microsoft.Graph.Reports
    ```

2. Download the M365 Sizing script https://github.com/rubrikinc/rubrik-scripts-for-powershell/blob/master/Sizing/M365/Get-RubrikM365SizingInfo.ps1



## Usage

1. Open a PowerShell terminal and navigate to the folder/directory where you downloaded the script.
2. Run the script.
    ```
    ./Get-RubrikM365SizingInfo.ps1
    ```
3. Authenticate and acknowledge report access permissions in the browser window/tab that appears.
4. The script will run and the results will be written to a text file in the directory in which it was run. `.\RubrikMS365Sizing.txt`
5. The resulting output can be entered into the Rubrik M365 sizing tool.
