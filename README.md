# Photon OS on Azure

Actually VMware Photon OS is not an Azure Marketplace base operating system image. From a technical feasibility perspective of a new generation of marketplace offerings, time-limited hosting of OS releases and good practices of immutable infrastructure workflows still is a key feature for many customers. A few Linux distros Ubuntu, openSUSE, CentOS, SLES, Debian or CoreOS enjoy endorsed support by Azure. For customers with many Windows servers onpremise and a few Linux servers these offerings help to simplify their hybrid cloud infrastructure management journey. Here's a good starting tutorial on [managing static Linux VMs on Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/tutorial-custom-images).

To run Photon OS on Azure have a look to [Downloading Photon OS](https://github.com/vmware/photon/wiki/Downloading-Photon-OS). You will find for most releases the appropriate Azure VHD file.
In situations where you rather need a container, better have a look to https://hub.docker.com/_/photon.
In addition,
- You can customize Photon OS images with [Packer on Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/build-image-with-packer)
- You could use [Azure Image Builder](https://docs.microsoft.com/en-us/azure/virtual-machines/image-builder-overview)
- In situations where must-functions in Packer and/or Azure Image Builder are not desired/available, but available using Azure Powershell+CLI, it might be an affordable way to adopt a Scripted Azure image creation method.using the official VHD file of a specific VMware Photon OS build. See next chapter 'Photon OS on Azure - scripts'.


# Photon OS on Azure - scripts

In the sub directory "PhotonOS" you will find several scripts to deploy Photon OS Azure images and provision Photon OS virtual machines.

## create-AzImage-PhotonOS.ps1

The script creates an Azure image of a VMware Photon OS release for Azure. Simply start the script using following parameters: 

```./create-AzImage-PhotonOS.ps1 -DownloadURL "https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz" -ResourceGroupName <your resource group> -Location <your location> -HyperVGeneration <V1/V2>```

Don't worry if you don't know the public URLs. Those are included as ValidateSet inside the script so you can easily copy&paste the preferred url.

Prerequisites are:
- Script must run on MS Windows OS with Powershell PSVersion 5.1 or higher
- Azure account with Virtual Machine contributor role

The script uses the VHD file url of a VMware Photon OS build.
You can pass a bunch of parameters eg. Azure device login, resourcegroup, location name, storage account, container, image name, etc. The script tries to install to your local computer if necessary the Powershell Az 8.0 module.  
Afterwards it connects to your Azure subscription and saves the Az-Context. It checks/creates resource group, virtual network, storage account/container/blob and settings for a temporary windows server virtual machine. The VMware Photon OS bits for Azure are downloaded from the VMware download location, and the extracted VMware Photon OS .vhd is uploaded as Azure page blob from inside the temporary virtual machine. The temporary virtual machine created is Microsoft Windows Server 2019 on a Hyper-V Generation V1 or V2 virtual hardware using the offering Standard_E4s_v3. This allows the creation of Generation V1 or V2 virtual machines. Using the AzVMCustomScriptExtension functionality, dynamically created scriptblocks including passed Az-Context are used to postinstall the necessary prerequisites inside that Microsoft Windows Server vm.  
Afterwards the image has been created, the Microsoft Windows Server vm is deleted.  
You find the VMware Photon OS HyperV Generation V1 or V2 image stored in your Azure resource group. Default is V2 and the name of the image ends with "_V2.vhd". 

Have a look to the test script ```create-AzImage-PhotonOS-AllVersions.ps1``` as well. It uses ```create-AzImage-PhotonOS.ps1``` to create the V1 and V2 Azure Images of all VMware Photon OS releases

<img src="https://github.com/dcasota/azure-scripts/blob/master/PhotonOS/VMware.PhotonOS.hyperscalers.Azure.png" align="left" />
<br clear="left"/><br clear="both"/>

## create-AzVM_FromImage-PhotonOS.ps1

The script provisions an Azure VM from an existing VMware Photon OS Azure Image. Start the script using following parameters: 

```./create-AzVM_FromImage-PhotonOS.ps1 -Location <location> -ResourceGroupNameImage <resource group of the Azure image> -ImageName <image name ending with .vhd> -ResourceGroupName <resource group of the new VM> -VMName <VM name>```

The script supports many additional parameters. It can be used for more advanced lab setups as well.

Per default, the VM size is Standard_B1ms.

Have a look to the optional script parameter values. As example, a local user account on Photon OS will be created during provisioning. There are some password complexity rules to know.
- ```[string]$VMLocalAdminUser = "Local"``` # Check if uppercase and lowercase is enforced/supported.
- ```[string]$VMLocalAdminPwd="Secure2020123."```# 12-123 chars

The script checks/creates resource group, virtual network, storage account/container/blob and the virtual machine.

## create-AzImage-PhotonOS-AllVersions.ps1

This is a test script which creates the V1 and V2 Azure Images of all VMware Photon OS releases. Just start it. The creation of all versions takes a while.

Keep in mind it's a test script. From earlier tests results, sometimes the whole creation sequence stopped suddenly and on a different Photon OS release version as on the last run. As workaround simply rerun the creation only of the missing versions.

# When to use Azure Generation V2 virtual machine?
For system engineers knowledge about the VMware virtual hardware version is crucial when it comes to VM capabilities and natural limitations. Latest capabilities like UEFI boot type and virtualization-based security are still evolving. 
The same begins for cloud virtual hardware like in Azure Generations.
On Azure, VMs with UEFI boot type support are somewhat limited yet (see docs about trusted launch). However some downgrade options were made available to migrate such on-premises Windows servers to Azure by converting the boot type of the on-premises servers to BIOS while migrating them.

 Some docs artefacts about
- https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2#features-and-capabilities
- https://docs.microsoft.com/en-us/azure/virtual-machines/trusted-launch
- https://docs.vmware.com/en/VMware-vSphere/6.7/com.vmware.vsphere.vm_admin.doc/GUID-789C3913-1053-4850-A0F0-E29C3D32B6DA.html
- https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.vsphere.vm_admin.doc/GUID-789C3913-1053-4850-A0F0-E29C3D32B6DA.html

# VMware Tanzu Kubernetes Grid on Azure

VMware Tanzu Kubernetes Grid (TKG) Plus (see [KB article](https://kb.vmware.com/s/article/67389)) enables to deploy and run containerized workloads across private and public clouds. To run workloads across Azure you must have deployed a TKG cluster.

The management cluster is the first cluster and must run on an optimized compute environment. Usually this is a VMware vSphere environment. You can deploy the management cluster (see [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.5/vmware-tanzu-kubernetes-grid-15/GUID-mgmt-clusters-deploy-management-clusters.html) on
1. your VMware vSphere environment
2. your Azure VMware Solution Tenant (see [AVS](https://cloud.vmware.com/azure-vmware-solution))
3. Azure Hyper-V resources for testing purposes

Most VMware appliances' OS is a striped-down, commercialized sort of Photon OS, optimized to run best on ESXi. This matches with cases one and two.

For AVS Tenant and Azure Hyper-V ressources there is a ready-to-use TKG application Azure offering on top on Ubuntu: ```get-azvmimagesku -Location Switzerlandnorth -PublisherName vmware-inc -Offer tkg-capi```

In reference to [Tanzu Kuberneted Grid on Azure docs](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.5/vmware-tanzu-kubernetes-grid-15/GUID-mgmt-clusters-azure.html) a supported plan is k8s-1dot20dot4-ubuntu-2004.  
```
get-azvmimage -Location Switzerlandnorth -PublisherName vmware-inc -Offer tkg-capi -skus k8s-1dot20dot4-ubuntu-2004

Version    Skus                       Offer    PublisherName Location         Id                                                                                                                            
-------    ----                       -----    ------------- --------         --                                                                                                                            
2021.02.24 k8s-1dot20dot4-ubuntu-2004 tkg-capi vmware-inc    SwitzerlandNorth /Subscriptions/1f6820c3-1aec-4b3c-9a9b-da3a9b8810de/Providers/Microsoft.Compute/Locations/SwitzerlandNorth/Publishers/vmwar...
2021.03.05 k8s-1dot20dot4-ubuntu-2004 tkg-capi vmware-inc    SwitzerlandNorth /Subscriptions/1f6820c3-1aec-4b3c-9a9b-da3a9b8810de/Providers/Microsoft.Compute/Locations/SwitzerlandNorth/Publishers/vmwar...
```

# VMware Tanzu Kubernetes Grid on Azure - scripts

This repo contains Azure Powershell helper scripts for VMware Tanzu Kubernetes Grid on Azure.

```TKG-CAPI-Install.ps1```
The script deploys the Azure TKG-CAPI virtual machine. Simply modify all variables right at the beginning. The setup works with the sku k8s-1dot20dot4-ubuntu-2004 on version 2021.03.05.
Prerequisites are:
- Script must run on MS Windows OS with Powershell PSVersion 5.1 or higher
- Azure account with Virtual Machine contributor role

It installs Powershell Az module if necessary on your local computer. Afterwards the script connects to Azure and checks/creates resource group, storage account, virtual network with a public ip and a network security group with rules for ports 22 and 6443, and deploys the virtual machine from the marketplace tkg-capi image.



# Archive

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
