# Azure scripts  Microsoft Windows Server virtual machine related

You find in this repo some Azure study scripts easily to deploy a Windows or Linux server on Azure.

```W2K19-Install.ps1```
Deploys the Azure template Windows Server 2019 Datacenter. You can mark the line beginning with ```Set-AzVMCustomScriptExtension``` as comment (#). If uncommented, after the setup, it launches the ```MonoOnW2K19-install.ps1```.

```W2K19-HyperVGenV2-Install.ps1```
Deploys the Azure template Windows Server 2019 Datacenter HyperV-Generation V2.

```MSSQL14onW2K12R2-Install.ps1```
Deploys the Azure template Microsoft SQL Server 2014 on a Windows Server 2012 R2.

# Azure scripts Linux virtual machine related
```Ubuntu18.04-Install.ps1```
Deploys the Azure template Canonical Ubuntu 18.04 Server.

```MonoOnW2K19-install.ps1```
This post-provisioning script is called by ```W2K19-Install.ps1```. It downloads and installs Mono (#todo not finished yet).

# Azure scripts VMware Photon OS virtual machine related

```create-AzVM_FromImage-PhotonOS.ps1```
The script creates an Azure Generation V1 or V2 VM from a individual VMware Photon OS Azure Image.

```create-AzImage-PhotonOS.ps1```
The script creates an Azure image of a VMware Photon OS release for Azure. Simply start the script using following parameters: 

```./create-AzImage-PhotonOS.ps1 -cred $(Get-credential -message 'Enter a username and password for Azure login.') -ResourceGroupName <YourResourceGroup> -Location <YourLocation> -StorageAccountName <YourStorageAccount> -ContainerName disks```

Without additional parameters the script creates an Azure image of VMware Photon OS photon-azure-3.0-935540.

The download URL of VMware Photon OS 3.0 Rev2 is stored as default value in SoftwareToProcess. The optional script parameters have predefined values. After the script has finished, you find the VMware Photon OS HyperV Generation V1 or V2 image stored in your ResourceGroup. 

To make use of VMware Photon OS on Azure, the script first creates a temporary Windows VM. Inside that Windows VM the VMware Photon OS bits for Azure are downloaded from the VMware download location, the extracted VMware Photon OS .vhd is uploaded as Azure page blob and after the image has been created, the Windows VM is deleted. The temporary VM created is Microsoft Windows Server 2019 on a Hyper-V Generation virtual hardware using the offering Standard_E4s_v3. This allows the creation of Generation V1 or V2 virtual machines.

## Archive
```create-AzImage_GenV2-PhotonOS.ps1``` creates an Azure Generation V2 image of VMware Photon OS. This script is deprecated. Use ```create-AzImage-PhotonOS.ps1```.
