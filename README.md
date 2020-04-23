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

To make use of VMware Photon OS on Azure, actually there is no deploy function of a Photon OS template on Azure, so we manually process the bits through two helper scripts.

```create-AzImage-PhotonOS.ps1```
The script creates an Azure image of a VMware Photon OS release for Azure.

```create-AzVM_FromImage-PhotonOS.ps1```
The script creates an Azure VM from a individual VMware Photon OS Azure Image.

Download both scripts. You can pass a bunch of parameters like Azure login, resourcegroup, location name, storage account, container, image name, etc. The first script passes the download URL of the VMware Photon OS release. More information: https://github.com/vmware/photon/wiki/Downloading-Photon-OS.
Prerequisites for both scripts are:
- Windows Powershell
- a Microsoft Azure account

```create-AzImage-PhotonOS.ps1``` installs Azure CLI and the Powershell Az module if necessary on your local computer. If wanted for that case, you need to start the script with administrative privileges.

Afterwards the script connects to Azure and saves the Az-Context. It checks/creates
- resource group
- virtual network
- storage account/container/blob
- settings for a temporary VM

Simply start the script using following parameters: 

```./create-AzImage-PhotonOS.ps1 -cred $(Get-credential -message 'Enter a username and password for Azure login.') -ResourceGroupName <YourResourceGroup> -Location <YourLocation> -StorageAccountName <YourStorageAccount>```

Without additional parameters the script creates an Azure image of VMware Photon OS photon-azure-3.0-935540. The download URL of VMware Photon OS 3.0 Rev2 is stored as default value of an optional param SoftwareToProcess. Other optional script parameters have predefined values, too.

The script creates a temporary Microsoft Windows Server VM. The VMware Photon OS bits for Azure are downloaded from the VMware download location, the extracted VMware Photon OS .vhd is uploaded as Azure page blob and after the image has been created, the Microsoft Windows Server VM is deleted. The temporary VM created is Microsoft Windows Server 2019 on a Hyper-V Generation V1 or V2 virtual hardware using the offering Standard_E4s_v3. This allows the creation of Generation V1 or V2 virtual machines. Using the AzVMCustomScriptExtension functionality, dynamically created scriptblocks including passed Az-Context are used to postinstall the necessary prerequisites inside that Microsoft Windows Server VM. 

After the script has finished, you find the VMware Photon OS HyperV Generation V1 or V2 image stored in your ResourceGroup.

Using ```create-AzVM_FromImage-PhotonOS.ps1``` you pass Photon OS VM settings. Start the script using following parameters: 

```./create-AzVM_FromImage-PhotonOS.ps1 -cred $(Get-credential -message 'Enter a username and password for Azure login.') -ResourceGroupName <YourResourceGroup> -Location <YourLocation> -StorageAccountName <YourStorageAccount> -ImageName <ImageName> -VMName <VMName>```

Have a look to the optional script parameter values. As example, a local user account on Photon OS will be created during provisioning. It is created without root permissions. There are some culprit to know.
- ```[string]$VMLocalAdminUser = "LocalAdminUser"``` # Check if uppercase and lowercase is enforced/supported.
- ```[string]$VMLocalAdminPwd="Secure2020123!"```# 12-123 chars

The script checks/creates
- resource group
- virtual network
- storage account/container/blob
- vm

It finishes with enabling the Azure boot-diagnostics option.


When to use Azure Generation V2 virtual machine?
For system engineers knowledge about the VMware virtual hardware version is crucial when it comes to VM capabilities and natural limitations. Latest capabilities like UEFI boot type and virtualization-based security are still evolving. 
The same begins for cloud virtual hardware like in Azure Generations.
On Azure, VMs with UEFI boot type are not supported yet. However some downgrade options were made available to migrate such on-premises Windows servers to Azure by converting the boot type of the on-premises servers to BIOS while migrating them.

 Some docs artefacts about
- https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2#features-and-capabilities
- https://docs.vmware.com/en/VMware-vSphere/6.7/com.vmware.vsphere.vm_admin.doc/GUID-789C3913-1053-4850-A0F0-E29C3D32B6DA.html


## Archive
```create-AzImage_GenV2-PhotonOS.ps1``` creates an Azure Generation V2 image of VMware Photon OS. This script is deprecated. Use ```create-AzImage-PhotonOS.ps1```.
