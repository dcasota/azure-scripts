# Azure scripts VMware Photon OS virtual machine related

Actually there are no official Azure marketplace VM images of VMware Photon OS. In situations where you rather need a container, better have a look to https://hub.docker.com/_/photon.

From a technical feasibility perspective of a new generation of marketplace offerings, time-limited hosting of OS releases and good practices of immutable infrastructure workflows still is a key feature for many customers. A few classic Linux distros Ubuntu, openSUSE, CentOS, SLES, Debian or CoreOS enjoy endorsed support by Azure. For customers with many Windows servers onpremise and a few Linux servers these offerings help to simplify their hybrid cloud infrastructure management journey. Here's a good starting tutorial on [managing static Linux VMs on Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/tutorial-custom-images).

From a multi-cloud perspective VMware Tanzu Kubernetes Grid Plus (see [KB article](https://kb.vmware.com/s/article/78173)) engages infrastructure workflow solutions to integrate at the level of a Kubernetes Node OS.

Okay, but I cannot easily register an Azure endpoint on VMware vCenter and simply push a Photon OS image from the content libray to my Azure tenant. Yes, this isn't possible yet, but you can make use of Photon OS builds on Azure with limited infrastructure workflows. Have a look to https://github.com/vmware/photon/wiki/Downloading-Photon-OS. You will find for most releases the appropriate Azure VHD file.
In addition,
- You can create Photon OS images with [Packer on Azure] (https://docs.microsoft.com/en-us/azure/virtual-machines/linux/build-image-with-packer).
- There is a technical preview of the upcoming [Azure Image Builder] (https://docs.microsoft.com/en-us/azure/virtual-machines/image-builder-overview).
- In situations where must-functions in Packer and/or Azure Image Builder are not available yet, but available using Azure Powershell+CLI, it has been an affordable way to adopt a Scripted Azure image creation method. It uses a mix of Azure Powershell+CLI with the official ISO or VHD file of a specific VMware Photon OS build. Actually, this repo shares findings specifically on provisioning VMware Photon OS on Azure using Scripted Azure image creation.

![VMware Photon OS Azure Images](https://github.com/dcasota/azure-scripts/blob/master/VMware-Photon-OS-Azure-Images.png)


# Scripted Azure image creation
This repo contains two Azure Powershell+CLI helper scripts for a Photon OS Azure image creation.

```create-AzImage-PhotonOS.ps1```
The script creates an Azure image of a VMware Photon OS release for Azure. It uses the VHD file url of a VMware Photon OS build.

```create-AzVM_FromImage-PhotonOS.ps1```
The script creates an Azure VM from an individual VMware Photon OS Azure Image.

Download both scripts. You can pass a bunch of parameters like Azure device login, resourcegroup, location name, storage account, container, image name, etc. The first script passes the download URL of the VMware Photon OS release. More information: https://github.com/vmware/photon/wiki/Downloading-Photon-OS.
Prerequisites for both scripts are:
- Script must run on MS Windows OS with Powershell PSVersion 5.1 or higher
- Azure account with Virtual Machine contributor role

```create-AzImage-PhotonOS.ps1``` installs Azure CLI and the Powershell Az module if necessary on your local computer.

Afterwards the script connects to Azure and saves the Az-Context. It checks/creates
- resource group
- virtual network
- storage account/container/blob
- settings for a temporary VM

Simply start the script using following parameters: 

```./create-AzImage-PhotonOS.ps1 -SoftwareToProcess "https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz" -ResourceGroupName <your resource group> -Location <your location>```

The sscript creates an Azure image of VMware Photon OS photon-azure-4.0-1526e30ba. The download URL of VMware Photon OS 4.0 GA is stored as default value of an optional param SoftwareToProcess. Other optional script parameters have predefined values, too.

The script creates a temporary Microsoft Windows Server VM. The VMware Photon OS bits for Azure are downloaded from the VMware download location, the extracted VMware Photon OS .vhd is uploaded as Azure page blob and after the image has been created, the Microsoft Windows Server VM is deleted. The temporary VM created is Microsoft Windows Server 2019 on a Hyper-V Generation V1 or V2 virtual hardware using the offering Standard_E4s_v3. This allows the creation of Generation V1 or V2 virtual machines. Using the AzVMCustomScriptExtension functionality, dynamically created scriptblocks including passed Az-Context are used to postinstall the necessary prerequisites inside that Microsoft Windows Server VM. 

After the script has finished, you find the VMware Photon OS HyperV Generation V1 or V2 image stored in your ResourceGroup. Default is V2 and the name of the image ends with "V2.vhd".

```create-AzVM_FromImage-PhotonOS.ps1``` provisions a VM from an Azure image. Start the script using following parameters: 

```./create-AzVM_FromImage-PhotonOS.ps1 -Location <location> -ResourceGroupNameImage <resource group of the Azure image> -ImageName <image name ending with .vhd> -ResourceGroupName <resource group of the new VM> -VMName <VM name>```

Have a look to the optional script parameter values. As example, a local user account on Photon OS will be created during provisioning. There are some password complexity rules to know.
- ```[string]$VMLocalAdminUser = "Local"``` # Check if uppercase and lowercase is enforced/supported.
- ```[string]$VMLocalAdminPwd="Secure2020123."```# 12-123 chars

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

```Ubuntu18.04-Install.ps1```
Deploys the Azure template Canonical Ubuntu 18.04 Server.

```create-AzVMNodeRed_FromImage-PhotonOS.ps1```
Deploys a VMware Photon OS VM with installed Siemens MindConnect Node-Red editor.
Example provisioning: ```.\create-AzVMNodeRed_FromImage-PhotonOS.ps1 -LocationName switzerlandnorth -ResourceGroupName photonoslab-rg -StorageAccountName photonoslab -ImageName photon-azure-3.0-9355405.vhd -ContainerName disks -VMName nodered1 -VMSize Standard_B1ms```
Requirements: Azure image of VMware Photon OS (see first chapter).

```W2K19-Install.ps1```
Deploys the Azure template Windows Server 2019 Datacenter. You can mark the line beginning with ```Set-AzVMCustomScriptExtension``` as comment (#). If uncommented, after the setup, it launches the ```MonoOnW2K19-install.ps1```.

```W2K19-HyperVGenV2-Install.ps1```
Deploys the Azure template Windows Server 2019 Datacenter HyperV-Generation V2.

```MSSQL14onW2K12R2-Install.ps1```
Deploys the Azure template Microsoft SQL Server 2014 on a Windows Server 2012 R2.
