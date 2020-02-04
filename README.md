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

```create-AzImage_GenV2-PhotonOS.ps1```
Actually there is no VMware Photon OS offering on the Azure marketplace. The script creates an Azure Generation V2 image of VMware Photon OS. To make use of VMware Photon OS on Azure, the script first creates a temporary Windows VM. Inside that Windows VM the VMware Photon OS bits for Azure are downloaded from the VMware download location, the extracted VMware Photon OS .vhd is uploaded as Azure page blob and after the Generation V2 image has been created, the Windows VM is deleted. For the .vhd file upload as Azure page blob a sub script ```Upload-PhotonVhd-as-Blob.ps1``` is used. For study purposes the temporary VM created is Microsoft Windows Server 2019 on a Hyper-V Generation V2 virtual hardware.
