#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    A script for install GLPI Agent

.DESCRIPTION
    A script for uninstall fusioninventory agent and install glpi agent with parameter, can also use github glpi agent repository for the installation

.PARAMETER RemoveFusionInventory
    Uninstall FusionInventory before install GLPIAgent

.PARAMETER Online
    Get GLPIAgent information from Github repositories

.PARAMETER OnlineSpecificVersion
    Specify a version to install with the winget way of installation

.PARAMETER InstallerPath
    Path to GLPI Agent installer msi file, if Online is not set, this param must be set

.PARAMETER InstallArgs
    Arguments used for installation, if you have to use string, use ` instead of \ for escape character 
.PARAMETER Winget
    Use winget instead of classic way with MSI File

.PARAMETER WingetSpecificVersion
    Specify a version to install with the winget way of installation

.PARAMETER DisableUpdate
    If this paramater is set, install GLPI Agent but don't try to upgrade it

.EXAMPLE
    Some examples for call this script:
    ./deployglpiagent.ps1 -Winget
    ./deployglpiagent.ps1 -Winget -WingetSpecificVersion "1.0"
    ./deployglpiagent.ps1 -InstallerPath GLPIAgent-Installer.msi
    ./deployglpiagent.ps1 GLPIAgent-Installer.msi
    ./deployglpiagent.ps1 -InstallerPath GLPIAgent-Installer.msi -InstallArgs "/qn"
    ./deployglpiagent.ps1 -Online
    ./deployglpiagent.ps1 -Online -OnlineSpecificVersion 1.0
    ./deployglpiagent.ps1 -Online -InstallArgs "/qn"
    ./deployglpiagent.ps1 -InstallerPath GLPIAgent-Installer.msi -InstallArgs "/qn" -RemoveFusionInventory
    ./deployglpiagent.ps1 -InstallerPath GLPIAgent-Installer.msi -InstallArgs "/qn" -RemoveFusionInventory -DisableUpdate

    if you have to use string in installer arguments, use this syntax:
    ./deployglpiagent.ps1 -InstallerPath GLPIAgent-Installer.msi -InstallArgs "/qn AGENTMONITOR_NEWTICKET_URL=`"http://127.0.0.1/`" "


.NOTES
Created by Loonaire (github.com/loonaire)
This code is under licence GNU GPL3
Script repository: https://github.com/loonaire/glpiagentdeploy
#>

param(
    [Parameter(HelpMessage = "If this arg is set, uninstall Fusion Inventory before install GLPI Agent")]
    [switch]$RemoveFusionInventory = $false,

    [Parameter(HelpMessage = "If this arg is set, use Github Repo instead of local msi file")]
    [switch]$Online = $false,   

    [Parameter(HelpMessage = "Specify the version to install from online source")]
    [string]$OnlineSpecificVersion = "", # NOTE You can customize the script with the version to download here  

    [Parameter(HelpMessage = "If this arg is set, use winget to install or upgrade instead of local file or github file")]
    [switch]$Winget = $false,   

    [Parameter(HelpMessage = "Specify the version to install from online source")]
    [string]$WingetSpecificVersion = "", # NOTE You can customize the script with the version to download with winget here  

    [Parameter(HelpMessage = "If this arg is set, don't update GLPI Agent")]
    [switch]$DisableUpdate = $false,   

    [Parameter(HelpMessage = "Path to GLPI Agent installer")]
    [string]$InstallerPath = "", # NOTE You can customize the installer path to use here

    [Parameter(HelpMessage = 'Arguments to use for GLPI Agent installion')]
    [string] $InstallArgs = "/qn" # NOTE You can customize the args to use here
    
)

$ErrorActionPreference = "Stop"

if (($Winget -ne $true) -and ($Online -ne $true)) {
    
    if ([string]::IsNullOrWhiteSpace($InstallerPath) -eq $true) {
        Write-Host "Error: Parameter Winget, Online or InstallerPath must be set" -ForegroundColor Red
        exit
    } elseif ($InstallerPath.EndsWith('.msi') -ne $true){
        # Because winget en online are not set, not enough parameter, need to have at least one way to install the software
        # Install via MSI file en the path to the file is unavailable
        Write-Host "$InstallerPath must be an '*.msi' file."
        exit
    } else {
        # NOTE if relative path is use, convert it to absolute path
        $InstallerPath = (Get-ChildItem $InstallerPath).FullName 
    }   
    
}


#----------- Functions ------------------
function Get-InstalledApplicationInfos {
    <#
    .SYNOPSIS
    Function to get some information about installed Application
    
    .DESCRIPTION
    Function to get Name, Version, Uninstall executable of installed Application
    
    .PARAMETER Name
    Specifies the name of the Application to search
    
    .EXAMPLE
    PS> Get-InstalledApplicationInfos Applicationname
    PS> Get-InstalledApplicationInfos -Name Applicationname
    
    .NOTES
    Inspired from https://www.sharepointdiary.com/2020/04/powershell-to-get-installed-software.html
    Some issues can be appeared, some softare are detected as multiple installation by Windows and because i use wildcard and like for search the Application, some Application can be undetected or the bad Application can be returned
    #>
    param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'Specifies the software name to get')]
        [string] $Name
    )

    $registryPath = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall", 
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall", 
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $registryPath) {
        $appInPath = Get-ChildItem -Path "$path" | Get-ItemProperty | Where-Object {($_.DisplayName -like "*$Name*")} | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString
        return $appInPath
    }
    return $Null
}

function Get-MSIProperties {
    <#
    .SYNOPSIS
    Function to get properties from MSI file
    
    .DESCRIPTION
    Function to get every properties of MSI file.
    Return simple MSI properties like ProductName, ProductVersion, ProductLanguage
    Custom properties for installation are return in SecureCustomProperties Member 
    
    .PARAMETER Path
    Specifies the full path to MSI file.
    
    .EXAMPLE
    PS> Get-MSIProperties file.msi
    PS> Get-MSIProperties -Path file.msi
    
    .NOTES
    Inspired from https://winadminnotes.wordpress.com/2010/04/05/accessing-msi-file-as-a-database/
    #>
    param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'Specifies path to MSI file.')][ValidateScript({
        if ($_.EndsWith('.msi')) {
            $true
        } else {
            throw ("{0} must be an '*.msi' file." -f $_)
        }
        })]
        [string] $Path
    )
    
    # Avoid error with the opening of msi database
    $Path = (Get-ChildItem -Path "$($Path)").FullName
    
    if (-not (Test-Path -Path $Path)) {
        Write-Error "Path is not valid $Path"
        return $Null
    }

    $MsiPropertiesObject = New-Object PSObject
    $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
    try {
        $Database = $WindowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $Null, $WindowsInstaller, @($Path,0))
        $View = $Database.GetType().InvokeMember("OpenView", "InvokeMethod", $Null, $Database, ("SELECT * FROM Property"))
        $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null)
        do {
            $Record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $Null, $View, $Null)
            if ($Null -ne $Record) {
                $PropertyName = $Record.GetType().InvokeMember("StringData", "GetProperty", $Null, $Record, 1)
                $PropertyValue = $Record.GetType().InvokeMember("StringData", "GetProperty", $Null, $Record, 2)
                $MsiPropertiesObject | Add-Member -MemberType NoteProperty -Name "$PropertyName" -Value "$PropertyValue"
            }

        } while ($Null -ne $Record)
        $View.GetType().InvokeMember('Close', "InvokeMethod", $Null, $View, $Null)  
    } catch {
        throw "Error on loading database of MSI file $_"
    }
    return $MsiPropertiesObject
}

function Remove-Application {
    <#
    .SYNOPSIS
    Function to remove an installed application
    
    .DESCRIPTION
    Function to remove an application from his UninstallString value
    
    .PARAMETER Command
    Specifies the Command to uninstall an application.
    
    .EXAMPLE
    PS> Remove-Application "uninstall command"
    PS> Get-MSIProperties -Command "uninstall command"
    
    .NOTES
    #>
    param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'Specifies Command to uninstall application')]
        [string] $Command
    )    
    
    if ($Command.EndsWith(".exe") -and -not ($Command.StartsWith("MsiExec"))) {
        # Simple exe file, start with /S arg  for silent uninstall
        Invoke-Command -ScriptBlock {& "$Command" /S} 
    } elseif( $Command.StartsWith("MsiExec.exe ")) {
        $executable = "MsiExec.exe"
        $executableArgs = $Command.Replace("MsiExec.exe ", "")
        Invoke-Command -ScriptBlock {& "$executable" $executableArgs} 
    } elseif ($Command.StartsWith('"')) {
        # Case if uninstall string already contain string
        Invoke-Command -ScriptBlock {& $executable} 

    } else {
        $splittedCommand = $Command.Split(".exe ")
        Invoke-Command -ScriptBlock {& "$(splittedCommand[0])" $splittedCommand[1]} 
    }
}

function Uninstall-FusionInventory {
    <#
    .SYNOPSIS
    Function tu uninstall Fusion Inventory
    
    .DESCRIPTION
    Uninstall fusion inventory if he is not installed
   
    .EXAMPLE
    PS> Uninstall-FusionInventory
    
    .NOTES
    #>

    $fusionInfos = Get-InstalledApplicationInfos -Name "FusionInventory"
    # Check if FusionInventory is installed
    if ($Null -ne $fusionInfos) {
        Remove-Application -Command $fusionInfos.UninstallString
    }    
}


function Install-GLPIAgent {
    <#
    .SYNOPSIS
    Install GLPI Agent
    
    .DESCRIPTION
    Install GLPI Agent
   
    .PARAMETER Path
    Path to GLPI Agent msi file

    .PARAMETER InstallationParameters
    String who contains parameters for GLPI Agent installer

    .EXAMPLE
    PS> Install-GLPIAgent file.msi $arguments
    PS> Install-GLPIAgent -Path file.msi -InstallationParameters $arguments
    #>
    param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'Specifies path to MSI file.')][ValidateScript({
        if ($_.EndsWith('.msi')) {
            $true
        } else {
            throw ("{0} must be an '*.msi' file." -f $_)
        }
        })]
        [string] $Path,
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Specifies the new version of the software")]
        [string]$InstallationParameters
    )
    
    Start-Process msiexec "/i $Path $InstallationParameters" -Wait
}

function Test-UpdateAvalaible {
    <#
    .SYNOPSIS
    Compare two software version
    
    .DESCRIPTION
    Compare two software version with the format X.Y return true if New version is newer than current version
    
    .PARAMETER CurrentVersion
    Specifies the current version of the software

    .PARAMETER NewVersion
    Specifies the new version of the software
    
    .EXAMPLE
    #>

    param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specifies the current version of the software")]
    [string]$CurrentVersion,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Specifies the new version of the software")]
    [string]$NewVersion    
    )

    $parsedCurrentVersion = $CurrentVersion.Split('.')
    $parsedNewVersion = $NewVersion.Split('.') 
    $isNewVersionNewer = $false

    if ([int]$parsedNewVersion[0] -gt [int]$parsedCurrentVersion[0]) {
        # Major version is newer
        $isNewVersionNewer = $true
    } elseif ( ([int]$parsedNewVersion[0] -eq [int]$parsedCurrentVersion[0]) -and ([int]$parsedNewVersion[1] -gt [int]$parsedCurrentVersion[1])) {
        $isNewVersionNewer = $true
    }
    return $isNewVersionNewer
}
function Get-OnlineVersion {
    <#
    .SYNOPSIS
    Get software version from github repo
    
    .DESCRIPTION
    Get info from github repo and get last version or specific version and the download url
 
    .EXAMPLE
    PS> Get-OnlineVersion
    PS> Get-OnlineVersion 1.0 # get version 1.0 download url of the software
    PS> Get-OnlineVersion --SpecificVersion 1.0 # get version 1.0 download url of the software
    #>

    param(
        [Parameter(Mandatory = $false, HelpMessage = "Specifies the specific version to download")]
        [string]$SpecificVersion
        )

    try {
        $repoUrl = "https://api.github.com/repos/glpi-project/glpi-agent/releases"
        
        $ProgressPreference = 'SilentlyContinue'
        if ([string]::IsNullOrWhiteSpace($SpecificVersion) -eq $false) {
            $jsonVersionAvalaible = ((Invoke-WebRequest "$repoUrl" -UseBasicParsing).Content | ConvertFrom-Json) | Where-Object {$_.draft -eq $False -and $_.prerelease -eq $False -and $_.tag_name -eq "$SpecificVersion"}  
        } else {
            $jsonVersionAvalaible = ((Invoke-WebRequest "$repoUrl" -UseBasicParsing).Content | ConvertFrom-Json) | Where-Object {$_.draft -eq $False -and $_.prerelease -eq $False}  
        }
        $ProgressPreference = 'Continue'

    } catch {
        throw $_
    }

    $jsonAssetData = $jsonVersionAvalaible[0].assets | Where-Object {$_.content_type -like "application/x-msi"}
    return @{
        Version = $jsonVersionAvalaible[0].tag_name
        Filename = $jsonAssetData.name
        DownloadUrl = $jsonAssetData.browser_download_url
    }
}

function Use-Winget{
    <#
    .SYNOPSIS
    Download and install a software with Winget from winget software id
    .DESCRIPTION
    Download and install a software with Winget from winget software id
    Can allow to do update or not with the parameter AllowUpdate
    .EXAMPLE
    #>
    param(
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Winget ID of the software to install")]
        [string]$SoftwareId,

        [Parameter(Mandatory = $false, Position = 2, HelpMessage = "If is set allow update of the software")]
        [switch]$AllowUpdate = $false,

        [Parameter(Mandatory = $false, Position = 3, HelpMessage = "Install the specific version if this parameter is set")]
        [string]$SpecificVersion,

        [Parameter(HelpMessage = 'Arguments to use for GLPI Agent installion (only use in install mode)')]
        [string] $InstallArgs = ""
        )
    
    # Test if the software is installed with winget list command. return more than one line if the soft is installed. By default winget return one line (no package installed message)
    # And if the update is allowed
    $wingetCheckSoftwareInstalled = $(winget list --id "$SoftwareId" -e --accept-source-agreements)
    if (($AllowUpdate -eq $true) -and ($wingetCheckSoftwareInstalled[$wingetCheckSoftwareInstalled.length-1] -like "*$SoftwareId*")) {
        winget upgrade --id "$SoftwareId" -e
    } else {
        if ([string]::IsNullOrWhiteSpace($SpecificVersion) -eq $false) {
            if ([string]::IsNullOrWhiteSpace($InstallArgs) -eq $true) {
                winget install --id "$SoftwareId" -e --version "$SpecificVersion"
            } else {
               winget install --id "$SoftwareId" -e --version "$SpecificVersion" --override "$InstallArgs" 
            }
           
        } else {
            # Install the last version by default
            if ([string]::IsNullOrWhiteSpace($InstallArgs) -eq $true) {
                winget install --id "$SoftwareId" -e
            } else {
                winget install --id "$SoftwareId" -e --override "$InstallArgs"
            }
        }
    }
}

function Use-ClassicInstallation{
     <#
    .SYNOPSIS
    Install or update GLPI Agent with msi file
    .DESCRIPTION
    Install or update GLPI Agent with msi file
    .EXAMPLE
    #>   
    
    param(
        [Parameter(HelpMessage = "If this arg is set, use Github Repo instead of local msi file")]
        [switch]$Online = $false,

        [Parameter(HelpMessage = "Specify the version to install from online source")]
        [string]$OnlineSpecificVersion = "",    

        [Parameter(HelpMessage = "If this arg is set, don't update GLPI Agent")]
        [switch]$DisableUpdate = $false,

        [Parameter(HelpMessage = "Path to GLPI Agent installer")]
        [string]$InstallerFullPath = "", 
    
        [Parameter(HelpMessage = 'Arguments to use for GLPI Agent installion')]
        [string] $InstallArgs = ""
        
    )
    # Get information about the state of glpi agent installation
    $GLPIAgentInstallationInfos = Get-InstalledApplicationInfos -Name "GLPI Agent"
    
    # If online param, compare version to repo version and download the installer
    if ($Online -eq $true) {
        if ([string]::IsNullOrWhiteSpace($OnlineSpecificVersion) -eq $true) {
            $OnlineInfos = Get-OnlineVersion
        } else {
            $OnlineInfos = Get-OnlineVersion -SpecificVersion "$OnlineSpecificVersion"
        }
        
        if (($Null -eq $GLPIAgentInstallationInfos) -or (($DisableUpdate -eq $false) -and (Test-UpdateAvalaible -CurrentVersion $GLPIAgentInstallationInfos.DisplayVersion -NewVersion $OnlineInfos.version)) ) {
            # GLPI Agent is not installed or an update is avalaible
            # Download the GLPI msi
            try {
                $ProgressPreference = 'SilentlyContinue'
                $downloadPath = "$env:temp\$($OnlineInfos.Filename)"
                Invoke-WebRequest "$($OnlineInfos.DownloadUrl)" -OutFile "$($downloadPath)" -UseBasicParsing            
                $ProgressPreference = 'Continue'
            } catch {
                throw $_
            }
    
            $GLPIAgentInstallerPath = "$((Get-ChildItem $downloadPath).FullName)"
        } else {
            # Update is disable or the previous check is false and the script must stop
            exit
        }
    } else {
        $GLPIAgentInstallerPath = "$InstallerFullPath"
    }
    
    $GLPIAgentInstallerInfos = Get-MSIProperties -Path $GLPIAgentInstallerPath
    
    # Check if installer file exist
    if((Test-Path -Path "$GLPIAgentInstallerPath" -IsValid) -eq $false) {
        Write-Error -Message "The path to GLPI Agent installer file does not exist $GLPIAgentInstallerPath"
        exit
    }
    
    if (($Null -eq $GLPIAgentInstallationInfos) -or (($DisableUpdate -eq $false) -and (Test-UpdateAvalaible -CurrentVersion $GLPIAgentInstallationInfos.DisplayVersion -NewVersion $GLPIAgentInstallerInfos.ProductVersion) -eq $true)) {
        # GLPI Agent is not installed or an update is avalaible
        if ([string]::IsNullOrWhiteSpace($InstallArgs)) {
            Install-GLPIAgent -Path "$GLPIAgentInstallerPath"
        } else {
            Install-GLPIAgent -Path "$GLPIAgentInstallerPath" -InstallationParameters "$InstallArgs"
        }
    }     
}


# --------------- MAIN -----------------------

if ($RemoveFusionInventory -eq $true) {
    Uninstall-FusionInventory
}

if ($Winget -eq $true) {
    $wingetArgs = @{
        AllowUpdate = if ($DisableUpdate -eq $true) {$true} else {$false};
        SoftwareId = "GLPI-Project.GLPI-Agent"
        SpecificVersion = if ([string]::IsNullOrWhiteSpace($WingetSpecificVersion) -eq $false) {$WingetSpecificVersion} else {""}
        InstallArgs = "$InstallArgs"
    }
    Use-Winget @wingetArgs
    exit
}

$classicInstallationArgs = @{
    Online = $Online
    OnlineSpecificVersion = "$OnlineSpecificVersion"
    DisableUpdate = $DisableUpdate
    InstallerFullPath = "$InstallerPath"
    InstallArgs = "$InstallArgs"
}
Use-ClassicInstallation @classicInstallationArgs