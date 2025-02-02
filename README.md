# Powershell GLPI Agent Deploy Script 

## Why this script?

I have some problems with the vbs script:
- vbs is not installed in Windows 11 by default (this is better for security) so the script will become unusable in the future
- vbs script need to be edited for each update of GLPI Agent, this script don't need modification and if he need modification this is because the dev team of GLPI Agent change github release name format
- This script support update, the vbs script doesn't
- For deploy with GPO you just have to edit the default values in the script args, you have nothing else to do 

### Why not use Winget?

I don't like winget, it's complicated to give install parameter and until few month GLPI Agent was not available in it.
Winget is also not available on all computer so it's better to not use it, i have also the advantage to get old versions from github (this is un idea for update this script later)

## How to use

Install from local file:
```powershell
./deployglpiagent.ps1 -InstallerPath "<GLPI Agent installer>" -InstallerArgs "<install args>" 
```

Install from Github repository:
```powershell
./deployglpiagent.ps1 -Online -InstallerArgs "<install args>" 
```

Remove Fusion inventory previous installation:
```powershell
./deployglpiagent.ps1 -InstallerPath "<GLPI Agent installer>" -InstallerArgs "<install args>" -RemoveFusionInventory
```

Install from Github repository (online installation, need internet connexion):
```powershell
./deployglpiagent.ps1 -Online -InstallerArgs "<install args>"
```
For download and install a specific version:
```powershell
./deployglpiagent.ps1 -Online -OnlineSpecificVersion "<version>" -InstallerArgs "<install args>"
```



For installation with winget (almost the same as -Online but use winget for download and install):
```powershell
./deployglpiagent.ps1 -Winget -InstallerArgs "<install args>"
```
For install a specific version:
```powershell
./deployglpiagent.ps1 -Winget -WingetSpecificVersion "<version>" -InstallerArgs "<install args>"
```

### Deploy via GPO

Because the args can be too long for gpedit.msc tool (the script don't start), you have to edit the script, i think this method is the more easiest to do:

- Edit the following lines:
```
76  [String]$InstallerPath = "", # NOTE You ca customize the installer path to use here
79  [String] $InstallArgs = "/qn" # NOTE You ca customize the args to use here
```
Line 76 (InstallerPath): Add the path to msi installer (or use InstallerPath param if you path is short) (can be omitted if -Online or -Winget is used)  
Line 79 (InstallArgs): Add the args to configure the GLPI Agent, you can find all documentation [here](https://glpi-agent.readthedocs.io/en/1.11/installation/windows-command-line.html#command-line-parameters). **Use ` for escape special characters, if you try to use \ the script will not work**.

> If you don't want use the GPO interface for set script parameter you can set others script parameter by changing the default parameters values at the top of the script.

> Because Winget is installed in user ``AppData/Local`` directory you can't use winget for deploy GLPI Agent with Computer Configuration GPO. You must start the powershell script in User Configuration and the user need to have the admin rights on the computer.


## Issues

Please create new issue
