# Photon OS on Azure

Actually VMware Photon OS is not an Azure Marketplace base operating system image. From a technical feasibility perspective of a new generation of marketplace offerings, time-limited hosting of OS releases and good practices of immutable infrastructure workflows is a desired feature. A few Linux distros Ubuntu, openSUSE, CentOS, SLES, Debian or CoreOS enjoy endorsed support by Azure. For customers with many Windows servers onpremise and a few Linux servers these offerings help to simplify their hybrid cloud infrastructure management journey. Here's a good starting tutorial on [managing static Linux VMs on Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/tutorial-custom-images).

To run Photon OS on Azure have a look to [Downloading Photon OS](https://github.com/vmware/photon/wiki/Downloading-Photon-OS). You will find for most releases the appropriate Azure VHD file.
In situations where you rather need a container, better have a look to https://hub.docker.com/_/photon.
In addition,
- You can customize Photon OS images with [Packer on Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/build-image-with-packer)
- You could use [Azure Image Builder](https://docs.microsoft.com/en-us/azure/virtual-machines/image-builder-overview)
- In situations where must-functions in Packer and/or Azure Image Builder are not desired/available, but available using Azure Powershell+CLI, it might be an affordable way to adopt a Scripted Azure image creation method using the official ISO or VHD file of a specific VMware Photon OS build. See next chapter 'Photon OS on Azure - scripts'.


# Photon OS on Azure - scripts

In the sub directory "PhotonOS" you will find several scripts to deploy Photon OS Azure images and provision Photon OS virtual machines.

The script-based solution works for **x86_64 and aarch64 (Arm64)**. The source can be a **web URL or a local file**, passed with the `-FilePath` parameter (`.iso`, `.vhd`, `.vhd.gz`, or `.vhd.tar.gz`). Architecture is taken from the file name (`aarch64` / `arm64` → Arm64, `x86_64` / `amd64` / `x64` → x64). A file name without those tokens is treated as x64. Use `-Architecture` to override.

| Source | Architectures | Result |
| --- | --- | --- |
| ISO (`-FilePath` URL or local file) | x86_64 and aarch64 | Azure Compute Gallery image (OsState Specialized). A VM created from that image boots the Photon OS installer. Gallery is used because managed images do not support Arm64. |
| VHD / VHD.tar.gz (`-FilePath` URL or local file) | x86_64 only | Managed image. The image name looks like `photon-azure-5.0-….x86_64_V2.vhd`. |

Local files are uploaded to a private, temporary blob container. The helper VM downloads the blob with a read-only SAS URL. The SHA256 of a local ISO is verified inside the helper VM. The temporary blob (and the storage account if the script created it) is deleted after the image is ready.

## create-AzImage-PhotonOS.ps1

The script creates an Azure image of a VMware Photon OS release for Azure. `-FilePath` accepts a web URL or a local file path.

ISO example (URL):

```powershell
./create-AzImage-PhotonOS.ps1 -FilePath "https://packages.vmware.com/photon/5.0/GA/iso/photon-5.0-dde71ec57.aarch64.iso" -ResourceGroupName PhotonOSTemplates -LocationName westeurope -HyperVGeneration V2
```

ISO example (local file, x86_64):

```powershell
./create-AzImage-PhotonOS.ps1 -FilePath "c:\users\dcaso\Downloads\Ph-Builds\photon-minimal-5.0-dde71ec57.x86_64.iso" -ResourceGroupName PhotonOSTemplates -LocationName switzerlandnorth
```

VHD example (URL, x86_64):

```powershell
./create-AzImage-PhotonOS.ps1 -FilePath "https://packages.vmware.com/photon/5.0/GA/azure/photon-azure-5.0-dde71ec57.x86_64.vhd.tar.gz" -ResourceGroupName PhotonOSTemplates -LocationName switzerlandnorth -HyperVGeneration V2
```

`-DownloadURL` is still accepted but deprecated; use `-FilePath`.

Don't worry if you don't know the public URLs. Those are included as ValidateSet inside the script so you can easily copy&paste the preferred url.

Prerequisites are:
- Script must run on MS Windows OS with Powershell PSVersion 5.1 or higher
- Azure account with Virtual Machine contributor role

You can pass a bunch of parameters eg. Azure device login, resourcegroup, location name, storage account, container, image name, helper VM size, Hyper-V generation, etc. The script tries to install to your local computer if necessary the Powershell Az module.
Afterwards it connects to your Azure subscription and saves the Az-Context.

**ISO workflow (x86_64 and aarch64):** a temporary Ubuntu 22.04 helper VM (Arm64 or x64, depending on `-HelperVMSize`) is created with an empty managed data disk. Inside the VM the data disk is prepared as a Ventoy bootable disk, the Photon OS ISO is placed on it, and the boot configuration is patched for the Azure serial console. The data disk is detached and published as an Azure Compute Gallery image version (OsState Specialized). Default helper VM size is `Standard_D2pls_v5` for aarch64 ISO files and `Standard_D2s_v3` for x86_64 ISO files. Arm64 requires Hyper-V Generation V2.

**VHD workflow (x86_64 only):** a temporary Windows Server helper VM downloads and extracts the Photon OS VHD and uploads it as an Azure page blob. A managed image is created. Default helper VM size is `Standard_E2s_v3`. Default Hyper-V generation is V2 and the name of the image ends with `_V2.vhd`.

The helper virtual machine size and the vCPU quota are checked before any resource is created. After the image has been created, helper resources are deleted.

Have a look to the test script `create-AzImage-PhotonOS-AllVersions.ps1` as well. It uses `create-AzImage-PhotonOS.ps1` to create the V1 and V2 Azure Images of all VMware Photon OS releases.

### Example: create an aarch64 template from a local ISO

```powershell
./create-AzImage-PhotonOS.ps1 -FilePath .\photon-5.0-3de6164e1.aarch64.azure.iso -ResourceGroupName PhotonOSTemplates -LocationName "UK South" -HyperVGeneration V2 -HelperVMSize Standard_D2pls_v6
```

Typical output:

```
Location 'UK South' is used as uksouth.
Photon OS Arm64 iso local file: photon-5.0-3de6164e1.aarch64.azure.iso
Location uksouth, resource group PhotonOSTemplates, HyperVGeneration V2, helper VM size Standard_D2pls_v6, image photon-5.0-3de6164e1.aarch64.azure_iso_V2
Computing SHA256 of .\photon-5.0-3de6164e1.aarch64.azure.iso ...
Uploading photon-5.0-3de6164e1.aarch64.azure.iso (4.17 GB) to the temporary blob container ph1884402510source of storage account photonos1884402510 ...
Creating data disk photon-5.0-3de6164e1.aarch64.azure_iso_V2_1884402510 ...
Creating helper VM ph1884402510 (Standard_D2pls_v6, Ubuntu 22_04-lts-arm64) ...
Preparing the Ventoy disk inside the helper VM. Downloading photon-5.0-3de6164e1.aarch64.azure.iso takes a while ...
WARNING: The extension output is not available, relying on the extension status Succeeded.
Detaching data disk photon-5.0-3de6164e1.aarch64.azure_iso_V2_1884402510 ...
Creating Azure Compute Gallery PhotonOS_uksouth ...
Creating image version 5.0.0 of photon-5.0-3de6164e1.aarch64.azure_iso_V2. This takes a few minutes ...
Image created: /subscriptions/<subscription-id>/resourceGroups/PhotonOSTemplates/providers/Microsoft.Compute/galleries/PhotonOS_uksouth/images/photon-5.0-3de6164e1.aarch64.azure_iso_V2/versions/5.0.0
Removing helper resources ...
Removed temporary blob ph1884402510source/photon-5.0-3de6164e1.aarch64.azure.iso.
Removed temporary storage account photonos1884402510.
```

<img src="https://github.com/dcasota/azure-scripts/blob/master/PhotonOS/VMware.PhotonOS.hyperscalers.Azure.png" align="left" />
<br clear="left"/><br clear="both"/>

## create-AzVM_FromImage-PhotonOS.ps1

The script provisions an Azure VM from an existing VMware Photon OS Azure Image (managed image or Azure Compute Gallery image). Start the script using following parameters:

```powershell
./create-AzVM_FromImage-PhotonOS.ps1 -LocationName <location> -ResourceGroupNameImage <resource group of the Azure image> -ImageName <image name> -ResourceGroupName <resource group of the new VM> -VMName <VM name>
```

For a gallery-based aarch64 ISO image, also pass `-GalleryName` and an Arm-capable `-VMSize`.

The script supports many additional parameters. It can be used for more advanced lab setups as well.

Per default, the VM size is Standard_B1ms (use an Arm64 size such as `Standard_D2pls_v6` when the image is aarch64).

Have a look to the optional script parameter values. As example, with VMLocalAdminCredential a local user account will be created during provisioning. There are some password complexity rules to know.

The script checks/creates resource group, virtual network, storage account/container/blob and the virtual machine.

### Example: consume an aarch64 template and create a VM

```powershell
./create-AzVM_FromImage-PhotonOS.ps1 -ResourceGroupNameImage PhotonOSTemplates -GalleryName PhotonOS_uksouth -ImageName photon-5.0-3de6164e1.aarch64.azure_iso_V2 -ResourceGroupName ph5arm -VMName ph5arm01 -VMSize Standard_D2pls_v6
```

Typical output:

```
Using HyperVGeneration V2.
Consider upgrading security for your workloads using Azure Trusted Launch VMs. To know more about Trusted Launch, please visit https://aka.ms/TrustedLaunch
RequestId IsSuccessStatusCode StatusCode ReasonPhrase
--------- ------------------- ---------- ------------
                         True         OK
VM ph5arm01 boots the Photon OS installer. Open the Azure serial console of the VM to proceed with the installation onto disk ph5arm01_installdisk (Linux, HyperVGeneration V2).
```

### After the VM has booted (ISO / installer image)

A VM created from an ISO gallery image boots the Photon OS installer. The VM has two disks: the specialized installer OS disk and a data disk (`<VMName>_installdisk`) that is the installation target. Complete the following steps after first boot:

* If it is an interactive setup, in Azure webportal, select the VM, go to Help → Serial console. Go through the setup wizard of Photon OS. Wait until the setup finishes and Photon OS is installed onto the data disk (`ph5arm01_installdisk` in the example above).
* The VM has two disks.
* Stop (deallocate) the VM.
  Overview → Stop. Wait until the status is Stopped (deallocated). This is the cleanest way to detach and swap.
* Detach the data disk.
  VM → Disks → on the `ph5arm01_installdisk` row, click the detach icon (link/chain on the right) → Save.
  Wait until the disk is no longer listed under Data disks (often 1–2 minutes; after a detach from another VM Microsoft suggests waiting up to 10–15 minutes if it does not appear).
* Swap the OS disk.
  Still on Disks, click Swap OS disk (the control already shown at the top of your screenshot).
  * Choose disk: `ph5arm01_installdisk`
  * Type the exact VM name to confirm
  * OK
* Start the VM and confirm it boots from the new disk.

December 1st 2025:
A deployed VM from photon-azure-5.0-9e778f409_V2.vhd has `/sbin` no in the PATH variables.
The following scripts fixes the issue.

```
#!/bin/bash

# Script to make PATH=$PATH:/sbin persistent system-wide by adding it to /etc/profile
# WARNING: This modifies a system file and affects all users. Run with sudo.

# Check if not run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run with sudo for system-wide changes."
    exit 1
fi

# Check if the line already exists in /etc/profile
if grep -q "export PATH=\$PATH:/sbin" /etc/profile; then
    echo "The PATH modification is already present in /etc/profile."
else
    # Append the export line to /etc/profile
    echo "export PATH=\$PATH:/sbin" >> /etc/profile
    echo "Added PATH modification to /etc/profile."
fi

# Source /etc/profile to apply changes immediately (for current session)
source /etc/profile

# Verify the change
echo "Current PATH: $PATH"
echo "Changes will persist across reboots for all users."
echo "Note: New login sessions or reboots may be required for other users to see the change."
```
To use this script:

Save it to a file, e.g., make_path_persistent_system.sh.
Make it executable: chmod +x make_path_persistent_system.sh.
Run it with sudo: sudo ./make_path_persistent_system.sh.


## create-AzImage-PhotonOS-AllVersions.ps1

This is a test script which creates the V1 and V2 Azure Images of all VMware Photon OS releases. Just start it. The creation of all versions takes a while.

Keep in mind it's a test script. From earlier tests results, sometimes the whole creation sequence stopped suddenly and on a different Photon OS release version as on the last run. As workaround, rerun the creation only for the missing versions eg. by putting a `#` at the line beginning of each version already processed.

# When to use Azure Generation V2 virtual machine?
For system engineers knowledge about the VMware virtual hardware version is crucial when it comes to VM capabilities and natural limitations. Latest capabilities like UEFI boot type and virtualization-based security are still evolving.
The same begins for cloud virtual hardware eg. in Azure Generations.
On Azure, VMs with UEFI boot type support are somewhat limited yet (see docs about trusted launch). However some downgrade options were made available to migrate such on-premises Windows servers to Azure by converting the boot type of the on-premises servers to BIOS while migrating them.

 Some docs artefacts about
- https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2#features-and-capabilities
- https://docs.microsoft.com/en-us/azure/virtual-machines/trusted-launch
- https://docs.vmware.com/en/VMware-vSphere/6.7/com.vmware.vsphere.vm_admin.doc/GUID-789C3913-1053-4850-A0F0-E29C3D32B6DA.html
- https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.vsphere.vm_admin.doc/GUID-789C3913-1053-4850-A0F0-E29C3D32B6DA.html
