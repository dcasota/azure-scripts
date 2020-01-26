# azure-scripts

You find in this repo some Azure study scripts easily to deploy a Windows or Linux server on Azure.

```W2K19-Install.ps1```
Deploys the Azure template Windows Server 2019 Datacenter. You can mark the line beginning with ```Set-AzVMCustomScriptExtension``` as comment (#). If uncommented, after the setup, it launches the ```MonoOnW2K19-install.ps1```.

```MSSQL14onW2K12R2-Install.ps1```
Deploys the Azure template Microsoft SQL Server 2014 on a Windows Server 2012 R2.

```Ubuntu18.04-Install.ps1```
Deploys the Azure template Canonical Ubuntu 18.04 Server.

```MonoOnW2K19-install.ps1```
This post-provisioning script is called by ```W2K19-Install.ps1```. It downloads and installs Mono (#todo not finished yet).


```W2K19-HyperVGenV2-Install```
Deploys the Azure template Windows Server 2019 Datacenter HyperV-Generation V2. 
