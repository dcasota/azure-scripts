# .SYNOPSIS
#  Deploy an Azure image of VMware Photon OS
#
# .DESCRIPTION
#  VMware Photon OS comes with multi-cloud support, use-case centric flavors, x86_64 and arm64 support and it supports virtual hardware generations.
#  On Azure actually, there are no official VMware Photon OS images. This may change. For the moment, this helper script deploys an Azure image of Photon OS.
#
#  It creates an Azure image of VMware Photon OS by an iso or vhd file. The file is given with -FilePath as web url or as local file path.
#  The resource group name is a mandatory parameter.
#  Without specifying further parameters, an Azure Arm64 image of the Photon OS 5.0 GA aarch64 iso is created in westeurope.
#
#  First, the script checks the Az module and triggers an Azure login using the device code method. You might see a similar message to
#    WARNUNG: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxxx to authenticate.
#  The Azure Powershell output shows up as warning (see above). Open a webbrowser, and fill in the code given by the Azure Powershell login output.
#
#  Iso file (x86_64 and aarch64):
#    A temporary Ubuntu 22.04 virtual machine (Arm64 or x64, depending on the helper VM size) is created with an empty managed data disk attached.
#    Inside the virtual machine, the data disk is configured as Ventoy bootable disk, the Photon OS iso file is downloaded onto it, and the boot configuration
#    is patched for the Azure serial console. The data disk is detached and published as Azure Compute Gallery image version (OsState Specialized).
#    A VM created from that image boots the Photon OS installer. Managed images do not support Arm64, hence the Azure Compute Gallery.
#    The gallery is named PhotonOS_<location>, the image definition looks like "photon-5.0-dde71ec57.aarch64_iso_V2".
#
#  Vhd file (x86_64 only):
#    A temporary Windows Server 2022 virtual machine downloads and extracts the Photon OS vhd, uploads it as page blob, and a managed image is created.
#    The name of the Azure image looks like "photon-azure-5.0-dde71ec57.x86_64_V2.vhd".
#    See Azure virtual hardware generation related weblink https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2
#
#  Local file:
#    A local file is uploaded to a private, temporary blob container of the storage account StorageAccountName. The helper VM downloads it with a
#    read-only SAS url. The SHA256 of a local iso file is verified inside the helper VM. The temporary blob only exists until the Azure image is ready,
#    it is deleted at the end of the script in any case, together with the storage account if the script created it.
#
#  The helper virtual machine size and the vCPU quota are checked before any resource is created. The cleanup deletes the temporary resources.
#
#  .PREREQUISITES
#    - Script must run on MS Windows OS with Powershell PSVersion 5.1 or higher
#    - Az.Compute 9.0 or higher
#    - Azure account with Virtual Machine contributor role
#    - vCPU quota for the helper VM size. Standard_D2pls_v5 (Arm64 default) requires the DPLSv5 family quota in the target location.
#    - Photon OS aarch64 kernels are built without CONFIG_HYPERV. The installer of such an iso does not see any disk on an Azure Arm64 VM.
#
#
# .NOTES
#   Author:  Daniel Casota
#   Version:
#   0.1   16.02.2020   dcasota  First release
#   0.2   24.02.2020   dcasota  Minor bugfixes, new param HyperVGeneration
#   0.3   23.04.2020   dcasota  Minor bugfixes image name processing and nsg cleanup
#   0.4   24.06.2020   dcasota  Bugfix extract .vhd.gz file
#   0.5   08.07.2020   dcasota  ValidateLength and ValidatePattern added
#   0.6   19.09.2020   dcasota  check administrative privileges
#   0.7   18.11.2020   dcasota  Photon OS 4.0 Beta Azure Vhd added
#   0.8   29.11.2020   dcasota  fix login issue https://github.com/Azure/azure-powershell/issues/13337
#   0.9   01.03.2021   dcasota  download URLs updated. Scheduled runas as localadminuser fixed.
#   0.91  02.03.2021   dcasota  comment fix
#   0.92  21.03.2021   dcasota  bugfix photon 2.0 processing
#   0.93  07.04.2021   dcasota  Changed naming of DownloadURL, bugfixing
#   0.94  08.04.2021   dcasota  code description added
#   1.00  13.10.2021   dcasota  Photon OS 4.0 Rev1 Azure Vhd added
#   1.01  08.11.2021   dcasota  Enforced Azure powershell + cli version update, temp vm scheduled task bug fix
#   1.10  15.06.2022   dcasota  Bugfixing, substitution of Azure CLI commands with Azure Powershell commands, latest Photon OS release added
#   1.11  11.07.2022   dcasota  text changes
#   1.12  17.08.2022   dcasota  bugfixing
#   2.00  26.01.2023   dcasota  iso url support added (does not work yet, NO AARCH64 SUPPORT YET)
#   2.01  19.03.2023   dcasota  bugfix iso url support (TODO : aarch64 support, Linux HelperDiskname, replace hardcoded CustomScriptExtension version)
#   2.02  31.03.2023   dcasota  Photon 5.0 rc urls added
#   2.03  13.05.2023   dcasota  Photon 5.0 GA vhd url added, bugfix .x86_64.vhd extraction, Ventoy 1.0.91
#   2.10  14.09.2026   dcasota  aarch64 iso support. Iso urls are processed on a Linux helper VM and published to an Azure Compute Gallery.
#                               Default Photon OS 5.0 GA aarch64 iso, helper VM size Standard_D2pls_v5, location westeurope (aarch64) or switzerlandnorth.
#                               Bugfix serial console (Ventoy conf_replace of /boot/grub2/grub.cfg), private blob container, generated helper VM password,
#                               vm size and quota preflight check, rerun detection, cleanup on failure.
#   2.20  14.09.2026   dcasota  New parameter FilePath for web urls and local files. Local files are uploaded to a temporary blob, which is deleted at the end.
#                               DownloadURL is deprecated. Image and disk names are shortened to the Azure limits.
#
# .PARAMETER FilePath
#   Web url (http or https) or local file path of a VMware Photon OS .iso, .vhd, .vhd.gz or .vhd.tar.gz file.
#   The architecture is taken from the file name (aarch64 or x86_64). Examples of web urls:
#        Photon OS 5.0 GA Full ISO arm64                     https://packages.vmware.com/photon/5.0/GA/iso/photon-5.0-dde71ec57.aarch64.iso
#        Photon OS 5.0 GA Minimal ISO arm64                  https://packages.vmware.com/photon/5.0/GA/iso/photon-minimal-5.0-dde71ec57.aarch64.iso
#        Photon OS 5.0 GA Full ISO x86_64                    https://packages.vmware.com/photon/5.0/GA/iso/photon-5.0-dde71ec57.x86_64.iso
#        Photon OS 5.0 GA Minimal ISO x86_64                 https://packages.vmware.com/photon/5.0/GA/iso/photon-minimal-5.0-dde71ec57.x86_64.iso
#        Photon OS 5.0 RC Full ISO x86_64                    https://packages.vmware.com/photon/5.0/RC/iso/photon-5.0-4d5974638.x86_64.iso
#        Photon OS 5.0 RC Minimal ISO x86_64                 https://packages.vmware.com/photon/5.0/RC/iso/photon-minimal-5.0-4d5974638.x86_64.iso
#        Photon OS 5.0 RC Real-Time ISO x86_64               https://packages.vmware.com/photon/5.0/RC/iso/photon-rt-5.0-4d5974638.x86_64.iso
#        Photon OS 5.0 Beta Full ISO x86_64                  https://packages.vmware.com/photon/5.0/Beta/iso/photon-5.0-9e778f409.iso
#        Photon OS 4.0 Rev2 Full ISO x86_64                  https://packages.vmware.com/photon/4.0/Rev2/iso/photon-4.0-c001795b8.iso
#        Photon OS 4.0 Rev2 Full ISO arm64                   https://packages.vmware.com/photon/4.0/Rev2/iso/photon-4.0-c001795b8-aarch64.iso
#        Photon OS 4.0 Rev2 Minimal ISO x86_64               https://packages.vmware.com/photon/4.0/Rev2/iso/photon-minimal-4.0-c001795b8.iso
#        Photon OS 4.0 Rev2 Minimal ISO arm64                https://packages.vmware.com/photon/4.0/Rev2/iso/photon-minimal-4.0-c001795b8-aarch64.iso
#        Photon OS 4.0 Rev2 Real-Time ISO x86_64             https://packages.vmware.com/photon/4.0/Rev2/iso/photon-rt-4.0-c001795b8.iso
#        Photon OS 4.0 Rev1 Full ISO x86_64                  https://packages.vmware.com/photon/4.0/Rev1/iso/photon-4.0-ca7c9e933.iso
#        Photon OS 4.0 Rev1 Full ISO arm64                   https://packages.vmware.com/photon/4.0/Rev1/iso/photon-4.0-ca7c9e933-aarch64.iso
#        Photon OS 4.0 Rev1 Minimal ISO x86_64               https://packages.vmware.com/photon/4.0/Rev1/iso/photon-minimal-4.0-ca7c9e933.iso
#        Photon OS 4.0 Rev1 Real-Time ISO x86_64             https://packages.vmware.com/photon/4.0/Rev1/iso/photon-rt-4.0-ca7c9e933.iso
#        Photon OS 4.0 GA Full ISO x86_64                    https://packages.vmware.com/photon/4.0/GA/iso/photon-4.0-1526e30ba.iso
#        Photon OS 4.0 GA Full ISO arm64                     https://packages.vmware.com/photon/4.0/GA/iso/photon-4.0-1526e30ba-aarch64.iso
#        Photon OS 4.0 GA Minimal ISO x86_64                 https://packages.vmware.com/photon/4.0/GA/iso/photon-minimal-4.0-1526e30ba.iso
#        Photon OS 4.0 GA Real-Time ISO x86_64               https://packages.vmware.com/photon/4.0/GA/iso/photon-rt-4.0-1526e30ba.iso
#      VMware Photon OS Azure vhd download links:
#        Photon OS 5.0 GA Azure VHD                          https://packages.vmware.com/photon/5.0/GA/azure/photon-azure-5.0-dde71ec57.x86_64.vhd.tar.gz
#        Photon OS 5.0 RC Azure VHD                          https://packages.vmware.com/photon/5.0/RC/azure/photon-azure-5.0-4d5974638.x86_64.vhd.tar.gz
#        Photon OS 5.0 Beta Azure VHD                        https://packages.vmware.com/photon/5.0/Beta/azure/photon-azure-5.0-9e778f409.vhd.tar.gz
#        Photon OS 4.0 Rev2 Azure VHD                        https://packages.vmware.com/photon/4.0/Rev2/azure/photon-azure-4.0-c001795b8.vhd.tar.gz
#        Photon OS 4.0 Rev1 Azure VHD                        https://packages.vmware.com/photon/4.0/Rev1/azure/photon-azure-4.0-ca7c9e933.vhd.tar.gz
#        Photon OS 4.0 GA Azure VHD                          https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz
#        Photon OS 4.0 RC Azure VHD                          https://packages.vmware.com/photon/4.0/RC/azure/photon-azure-4.0-a3a49f540.vhd.tar.gz
#        Photon OS 4.0 Beta Azure VHD                        https://packages.vmware.com/photon/4.0/Beta/azure/photon-azure-4.0-d98e681.vhd.tar.gz
#        Photon OS 3.0 Revision 2 Azure VHD                  https://packages.vmware.com/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz
#        Photon OS 3.0 GA Azure VHD                          https://packages.vmware.com/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz
#        Photon OS 3.0 RC Azure VHD                          https://packages.vmware.com/photon/3.0/RC/azure/photon-azure-3.0-49fd219.vhd.tar.gz
#        Photon OS 3.0 Beta Azure VHD                        https://packages.vmware.com/photon/3.0/Beta/azure/photon-azure-3.0-5e45dc9.vhd.tar.gz
#        Photon OS 2.0 GA Azure VHD gz file:                 https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-304b817.vhd.gz
#        Photon OS 2.0 GA Azure VHD cloud-init provisioning  https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-3146fa6.tar.gz
#        Photon OS 2.0 RC Azure VHD - gz file                https://packages.vmware.com/photon/2.0/RC/azure/photon-azure-2.0-31bb961.vhd.gz
#        Photon OS 2.0 Beta Azure VHD                        https://packages.vmware.com/photon/2.0/Beta/azure/photon-azure-2.0-8553d58.vhd
# .PARAMETER DownloadURL
#   Deprecated, use FilePath. Accepts the download links listed above.
# .PARAMETER LocationName
#   Azure location name where to create or lookup the resources. Default is westeurope for aarch64 files, otherwise switzerlandnorth.
# .PARAMETER ResourceGroupName
#   resource group name
# .PARAMETER RuntimeId
#   random id used in names
# .PARAMETER StorageAccountName
#   storage account name for vhd files and for the temporary blob of local files
# .PARAMETER StorageKind
#   storage kind
# .PARAMETER StorageAccountType
#   storage account type
# .PARAMETER HyperVGeneration
#   Azure HyperVGeneration. Arm64 supports V2 only.
# .PARAMETER HelperVMSize
#   Size of the temporary helper VM. Default is Standard_D2pls_v5 for aarch64 iso files, Standard_D2s_v3 for x86_64 iso files and Standard_E2s_v3 for vhd files.
# .PARAMETER HelperVMDiskSizeGB
#   Size of the Ventoy data disk (iso file only)
# .PARAMETER GalleryName
#   Azure Compute Gallery name (iso file only). Default is PhotonOS_<LocationName>.
# .PARAMETER VentoyVersion
#   Ventoy release used to make the data disk bootable (iso file only)
# .PARAMETER SkipCleanup
#   Keep the helper VM and its resources, e.g. for troubleshooting. The temporary blob of a local file is deleted anyway.
#
# .EXAMPLE
#    ./create-AzImage-PhotonOS.ps1 -ResourceGroupName PhotonOSTemplates
#    ./create-AzImage-PhotonOS.ps1 -FilePath "https://packages.vmware.com/photon/5.0/GA/iso/photon-5.0-dde71ec57.aarch64.iso" -ResourceGroupName PhotonOSTemplates -LocationName westeurope -HelperVMSize Standard_D2pls_v5
#    ./create-AzImage-PhotonOS.ps1 -FilePath "c:\users\dcaso\Downloads\Ph-Builds\photon-minimal-5.0-dde71ec57.x86_64.iso" -ResourceGroupName PhotonOSTemplates -LocationName switzerlandnorth
#    ./create-AzImage-PhotonOS.ps1 -FilePath "https://packages.vmware.com/photon/5.0/GA/azure/photon-azure-5.0-dde71ec57.x86_64.vhd.tar.gz" -ResourceGroupName PhotonOSTemplates -LocationName switzerlandnorth -HyperVGeneration V2
#
#>

[CmdletBinding()]
param(
[Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()]
[string]$FilePath="https://packages.vmware.com/photon/5.0/GA/iso/photon-5.0-dde71ec57.aarch64.iso",

[Parameter(Mandatory = $false)]
[ValidateSet(
'https://packages.vmware.com/photon/5.0/GA/iso/photon-5.0-dde71ec57.aarch64.iso', `
'https://packages.vmware.com/photon/5.0/GA/iso/photon-minimal-5.0-dde71ec57.aarch64.iso', `
'https://packages.vmware.com/photon/5.0/GA/iso/photon-5.0-dde71ec57.x86_64.iso', `
'https://packages.vmware.com/photon/5.0/GA/iso/photon-minimal-5.0-dde71ec57.x86_64.iso', `
'https://packages.vmware.com/photon/5.0/GA/azure/photon-azure-5.0-dde71ec57.x86_64.vhd.tar.gz', `
'https://packages.vmware.com/photon/5.0/RC/iso/photon-5.0-4d5974638.x86_64.iso', `
'https://packages.vmware.com/photon/5.0/RC/azure/photon-azure-5.0-4d5974638.x86_64.vhd.tar.gz', `
'https://packages.vmware.com/photon/5.0/Beta/iso/photon-5.0-9e778f409.iso', `
'https://packages.vmware.com/photon/5.0/Beta/azure/photon-azure-5.0-9e778f409.vhd.tar.gz', `
'https://packages.vmware.com/photon/4.0/Rev2/iso/photon-4.0-c001795b8.iso', `
'https://packages.vmware.com/photon/4.0/Rev2/iso/photon-4.0-c001795b8-aarch64.iso', `
'https://packages.vmware.com/photon/4.0/Rev2/azure/photon-azure-4.0-c001795b8.vhd.tar.gz', `
'https://packages.vmware.com/photon/4.0/Rev1/azure/photon-azure-4.0-ca7c9e933.vhd.tar.gz', `
'https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz', `
'https://packages.vmware.com/photon/4.0/RC/azure/photon-azure-4.0-a3a49f540.vhd.tar.gz', `
'https://packages.vmware.com/photon/4.0/Beta/azure/photon-azure-4.0-d98e681.vhd.tar.gz', `
'https://packages.vmware.com/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz', `
'https://packages.vmware.com/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz', `
'https://packages.vmware.com/photon/3.0/RC/azure/photon-azure-3.0-49fd219.vhd.tar.gz', `
'https://packages.vmware.com/photon/3.0/Beta/azure/photon-azure-3.0-5e45dc9.vhd.tar.gz', `
'https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-304b817.vhd.gz', `
'https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-3146fa6.tar.gz', `
'https://packages.vmware.com/photon/2.0/RC/azure/photon-azure-2.0-31bb961.vhd.gz', `
'https://packages.vmware.com/photon/2.0/Beta/azure/photon-azure-2.0-8553d58.vhd')]
[String]$DownloadURL,

[Parameter(Mandatory = $false)]
[string]$LocationName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupName,

[Parameter(Mandatory = $false)]
[string]$RuntimeId = (Get-Random).ToString(),

[Parameter(Mandatory = $false)][ValidateLength(3,24)][ValidatePattern("^[a-z0-9]+$")]
[string]$StorageAccountName=("PhotonOS${RuntimeId}").ToLower(),

[Parameter(Mandatory = $false)]
[string]$StorageKind="StorageV2",

[Parameter(Mandatory = $false)]
[string]$StorageAccountType="Standard_LRS",

[Parameter(Mandatory = $false)][ValidateSet('V1','V2')]
[string]$HyperVGeneration="V2",

[Parameter(Mandatory = $false)]
[string]$HelperVMSize,

[Parameter(Mandatory = $false)][ValidateRange(8,64)]
[int]$HelperVMDiskSizeGB=16,

[Parameter(Mandatory = $false)]
[string]$GalleryName,

[Parameter(Mandatory = $false)]
[string]$VentoyVersion="1.1.17",

[Parameter(Mandatory = $false)]
[switch]$SkipCleanup
)

$ErrorActionPreference = 'Stop'

# DownloadURL is deprecated and maps to FilePath
if ($PSBoundParameters.ContainsKey('DownloadURL'))
{
    if ($PSBoundParameters.ContainsKey('FilePath')) { throw "Specify either -FilePath or the deprecated -DownloadURL, not both." }
    Write-Warning "-DownloadURL is deprecated. Use -FilePath."
    $FilePath = $DownloadURL
}

# File path processing: web url or local file
if ($FilePath -match '^https?://')
{
    $IsLocalFile = $false
    $Uri = $FilePath
    $DownloadFileName = [System.Uri]::UnescapeDataString(([System.Uri]$FilePath).AbsolutePath.Split('/')[-1])
}
else
{
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "File $FilePath not found." }
    $IsLocalFile = $true
    $LocalFile = Get-Item -LiteralPath $FilePath
    $DownloadFileName = $LocalFile.Name
    # a read-only SAS url of the temporary blob, set after the upload
    $Uri = $null
}
$IsIso = $DownloadFileName.ToLower().EndsWith('.iso')
if (-not ($IsIso -or ($DownloadFileName -match '\.(vhd|vhd\.gz|tar\.gz)$')))
{
    throw "$DownloadFileName is not a supported file type (.iso, .vhd, .vhd.gz, .vhd.tar.gz, .tar.gz)."
}
if ($DownloadFileName -match '[.-]aarch64\.(iso|vhd\.tar\.gz)$') { $Architecture = 'Arm64' } else { $Architecture = 'x64' }

if ($Architecture -eq 'Arm64')
{
    if (-not $IsIso) { throw "Only Photon OS aarch64 .iso files are supported. There is no aarch64 Azure vhd." }
    if ($PSBoundParameters.ContainsKey('HyperVGeneration') -and ($HyperVGeneration -ne 'V2')) { throw "Azure Arm64 virtual machines support HyperVGeneration V2 only." }
    $HyperVGeneration = 'V2'
}

if ([string]::IsNullOrEmpty($LocationName))
{
    if ($Architecture -eq 'Arm64') { $LocationName = 'westeurope' } else { $LocationName = 'switzerlandnorth' }
}

if ([string]::IsNullOrEmpty($HelperVMSize))
{
    if ($IsIso -and ($Architecture -eq 'Arm64')) { $HelperVMSize = 'Standard_D2pls_v5' }
    elseif ($IsIso) { $HelperVMSize = 'Standard_D2s_v3' }
    else { $HelperVMSize = 'Standard_E2s_v3' }
}

if ([string]::IsNullOrEmpty($GalleryName)) { $GalleryName = "PhotonOS_${LocationName}" }


function Get-AzSafeName([string]$Name, [int]$MaxLength)
{
    # Azure image, gallery and disk names allow letters, digits, '.', '_' and '-' with a limited length.
    # Longer names, e.g. of local builds, are shortened with a hash suffix to stay unique.
    $safe = ($Name -replace '[^A-Za-z0-9._-]', '-').Trim('.', '-', '_')
    if ($safe.Length -le $MaxLength) { return $safe }
    $hash = -join ([System.Security.Cryptography.SHA1]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Name))[0..3] | ForEach-Object { $_.ToString('x2') })
    return $safe.Substring(0, $MaxLength - 9).TrimEnd('.', '-', '_') + '-' + $hash
}

if ($IsIso)
{
    # Azure Compute Gallery image definition, e.g. photon-5.0-dde71ec57.aarch64_iso_V2, image version 5.0.0
    $ImageNameSuffix = "_iso_" + $HyperVGeneration
    $ImageName = (Get-AzSafeName -Name ($DownloadFileName -replace '\.iso$', '') -MaxLength (80 - $ImageNameSuffix.Length)) + $ImageNameSuffix
    if ($FilePath -match '/photon/(\d+)\.(\d+)/') { $ImageVersion = "$($Matches[1]).$($Matches[2]).0" }
    elseif ($DownloadFileName -match 'photon-(?:[a-z]+-)*(\d+)\.(\d+)-') { $ImageVersion = "$($Matches[1]).$($Matches[2]).0" }
    else { $ImageVersion = '1.0.0' }
}
else
{
    # Managed image, e.g. photon-azure-5.0-dde71ec57.x86_64_V2.vhd
    $ImageNameSuffix = "_" + $HyperVGeneration + ".vhd"
    $ImageName = (Get-AzSafeName -Name ($DownloadFileName -split [regex]::Escape('.vhd'))[0] -MaxLength (80 - $ImageNameSuffix.Length)) + $ImageNameSuffix
}

# SHA256 of the Ventoy linux package, verified inside the helper VM
$VentoyKnownSha256 = @{ '1.1.17' = '7fb4ed08cef6a6b4d39dd19260d8c80291a78dfdf9af7d461571e23cbbc43805' }
$VentoySha256 = $VentoyKnownSha256[$VentoyVersion]


# HelperVM settings
if ($IsIso) { $HelperVMComputerName = "ph${RuntimeId}" } else { $HelperVMComputerName = "w2k22${RuntimeId}" }
$HelperVMName = $HelperVMComputerName
$HelperVMContainerName = "${HelperVMComputerName}disks"
$HelperVMDataDiskName = (Get-AzSafeName -Name $ImageName -MaxLength (79 - $RuntimeId.Length)) + "_${RuntimeId}"
$HelperVMNetworkName = "${HelperVMComputerName}vnet"
$HelperVMSubnetAddressPrefix = "192.168.1.0/24"
$HelperVMVnetAddressPrefix = "192.168.0.0/16"
$HelperVMnsgName = "${HelperVMComputerName}nsg"
$HelperVMPublicIPDNSName="${HelperVMComputerName}dns"
$HelperVMNICName = "${HelperVMComputerName}nic"
$HelperVMLocalAdminUser = "photonadmin"
$HelperVMsize_TempPath="d:" # vhd file only: the file is downloaded and extracted on the temporary disk of the Windows helper VM.

# Temporary blob of a local file
$SourceContainerName = "${HelperVMComputerName}source"
$SourceSasValidityHours = 6
$script:SourceStorageContext = $null
$script:SourceStorageAccountCreated = $false


function New-HelperVMPassword
{
    # nobody logs in to the helper VM, the password only satisfies the Azure complexity rules
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return "Ph0!" + (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] }))
}
$HelperVMLocalAdminPwd = New-HelperVMPassword


function Get-AzResourceOrNull([scriptblock]$Query)
{
    try { & $Query } catch { $null }
}


function Test-HelperVMCapacity
{
    param([string]$Location, [string]$VMSize)

    $sku = Get-AzComputeResourceSku -Location $Location | Where-Object { ($_.ResourceType -eq 'virtualMachines') -and ($_.Name -ieq $VMSize) }
    if (-not $sku) { throw "VM size $VMSize is not offered in location $Location. Specify another -HelperVMSize or -LocationName." }
    if ($sku.Restrictions | Where-Object { ($_.ReasonCode -eq 'NotAvailableForSubscription') -and ($_.Type -eq 'Location') })
    {
        throw "VM size $VMSize is restricted for this subscription in location $Location."
    }

    $vCPUs = [int](($sku.Capabilities | Where-Object Name -eq 'vCPUs').Value)
    $usage = Get-AzVMUsage -Location $Location
    foreach ($quota in @(($usage | Where-Object { $_.Name.Value -ieq $sku.Family }), ($usage | Where-Object { $_.Name.Value -ieq 'cores' })))
    {
        if ($quota -and (($quota.Limit - $quota.CurrentValue) -lt $vCPUs))
        {
            throw "Not enough vCPU quota for $VMSize in ${Location}: $($quota.Name.LocalizedValue) $($quota.CurrentValue)/$($quota.Limit), $vCPUs needed. Request a quota increase or specify another -HelperVMSize (e.g. Standard_D2pls_v6 for Arm64)."
        }
    }

    $cpuArchitecture = ($sku.Capabilities | Where-Object Name -eq 'CpuArchitectureType').Value
    if ([string]::IsNullOrEmpty($cpuArchitecture)) { $cpuArchitecture = 'x64' }
    $tempDiskMB = ($sku.Capabilities | Where-Object Name -eq 'MaxResourceVolumeMB').Value
    if ([string]::IsNullOrEmpty($tempDiskMB)) { $tempDiskMB = 0 }
    return [pscustomobject]@{
        Architecture      = $cpuArchitecture
        HyperVGenerations = ($sku.Capabilities | Where-Object Name -eq 'HyperVGenerations').Value
        TempDiskMB        = [int]$tempDiskMB
    }
}


function New-HelperVMNetwork
{
    # No inbound rules. The standard public IP provides outbound internet access for the downloads.
    $nsg = New-AzNetworkSecurityGroup -Name $HelperVMnsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -Force
    $subnet = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet -AddressPrefix $HelperVMSubnetAddressPrefix -NetworkSecurityGroup $nsg
    $vnet = New-AzVirtualNetwork -Name $HelperVMNetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $HelperVMVnetAddressPrefix -Subnet $subnet -Force
    $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $HelperVMPublicIPDNSName -AllocationMethod Static -Sku Standard -IdleTimeoutInMinutes 4 -Force
    return New-AzNetworkInterface -Name $HelperVMNICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id -Force
}


function Remove-HelperVMResources
{
    $steps = [ordered]@{
        "virtual machine $HelperVMName" = {
            $vm = Get-AzResourceOrNull { Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName }
            if ($vm)
            {
                $osDiskName = $vm.StorageProfile.OsDisk.Name
                $null = Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName -Force
                if (Get-AzResourceOrNull { Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $osDiskName }) { $null = Remove-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $osDiskName -Force }
            }
        }
        "network interface $HelperVMNICName" = { if (Get-AzResourceOrNull { Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $HelperVMNICName }) { $null = Remove-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $HelperVMNICName -Force } }
        "public ip $HelperVMPublicIPDNSName" = { if (Get-AzResourceOrNull { Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $HelperVMPublicIPDNSName }) { $null = Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $HelperVMPublicIPDNSName -Force } }
        "virtual network $HelperVMNetworkName" = { if (Get-AzResourceOrNull { Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HelperVMNetworkName }) { $null = Remove-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HelperVMNetworkName -Force } }
        "network security group $HelperVMnsgName" = { if (Get-AzResourceOrNull { Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $HelperVMnsgName }) { $null = Remove-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $HelperVMnsgName -Force } }
        "disk $HelperVMDataDiskName" = { if (Get-AzResourceOrNull { Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $HelperVMDataDiskName }) { $null = Remove-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $HelperVMDataDiskName -Force } }
    }
    foreach ($step in $steps.GetEnumerator())
    {
        try { & $step.Value } catch { Write-Warning "Cleanup of $($step.Key) failed: $($_.Exception.Message)" }
    }
}


function Publish-LocalFile
{
    # Uploads the local file to a private, temporary blob container and returns a read-only SAS url for the helper VM.
    $account = Get-AzResourceOrNull { Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName }
    if (-not $account)
    {
        $account = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind $StorageKind -SkuName $StorageAccountType -AllowBlobPublicAccess $false -MinimumTlsVersion TLS1_2
        $script:SourceStorageAccountCreated = $true
    }
    $script:SourceStorageContext = $account.Context
    if (-not (Get-AzResourceOrNull { Get-AzStorageContainer -Name $SourceContainerName -Context $account.Context }))
    {
        $null = New-AzStorageContainer -Name $SourceContainerName -Context $account.Context -Permission Off
    }
    $null = Set-AzStorageBlobContent -File $LocalFile.FullName -Container $SourceContainerName -Blob $DownloadFileName -BlobType Block -Context $account.Context -Force
    $sas = New-AzStorageBlobSASToken -Container $SourceContainerName -Blob $DownloadFileName -Permission r -Protocol HttpsOnly -ExpiryTime (Get-Date).ToUniversalTime().AddHours($SourceSasValidityHours) -Context $account.Context
    return $account.Context.BlobEndPoint + $SourceContainerName + '/' + [System.Uri]::EscapeDataString($DownloadFileName) + '?' + $sas.TrimStart('?')
}


function Remove-TemporarySourceBlob
{
    # The uploaded local file is only needed until the Azure image is ready.
    if (-not $script:SourceStorageContext) { return }
    try
    {
        if (Get-AzResourceOrNull { Get-AzStorageContainer -Name $SourceContainerName -Context $script:SourceStorageContext })
        {
            $null = Remove-AzStorageContainer -Name $SourceContainerName -Context $script:SourceStorageContext -Force
            write-output "Removed temporary blob $SourceContainerName/$DownloadFileName."
        }
        # The vhd flow removes its storage account itself.
        if ($script:SourceStorageAccountCreated -and $IsIso)
        {
            $null = Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force
            write-output "Removed temporary storage account $StorageAccountName."
        }
    }
    catch { Write-Warning "Cleanup of the temporary blob $SourceContainerName/$DownloadFileName failed: $($_.Exception.Message)" }
}


# Specify Tls
$TLSProtocols = [System.Net.SecurityProtocolType]::'Tls13',[System.Net.SecurityProtocolType]::'Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $TLSProtocols

# Check Azure Powershell
$AzComputeModule = Get-Module -Name Az.Compute -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if ((-not $AzComputeModule) -or ($AzComputeModule.Version -lt [version]'9.0.0'))
{
    write-output "Az.Compute 9.0 or higher is required (Arm64 disk and Azure Compute Gallery support)."
    write-output "Install it with: Install-Module -Name Az -Force -AllowClobber, and restart the Powershell session."
    return
}

$azconnect=$null
try
{
    # Already logged-in?
    $subscriptionId=(get-azcontext).Subscription.Id
    $TenantId=(get-azcontext).Tenant.Id
    # set subscription
    $null = select-AzSubscription -Subscription $subscriptionId -tenant $TenantId -ErrorAction Stop
    $azconnect=get-azcontext -ErrorAction SilentlyContinue
}
catch {}
if ([Object]::ReferenceEquals($azconnect,$null))
{
    try
    {
        $azconnect=connect-azaccount -devicecode
        $subscriptionId=(get-azcontext).Subscription.Id
        $TenantId=(get-azcontext).Tenant.Id
        # set subscription
        $null = select-AzSubscription -Subscription $subscriptionId -tenant $TenantId -ErrorAction Stop
    }
    catch
    {
        write-output "Azure Powershell login required."
        return
    }
}

write-output "Photon OS $Architecture $(if ($IsIso) {'iso'} else {'vhd'}) $(if ($IsLocalFile) {'local file'} else {'web url'}): $DownloadFileName"
write-output "Location $LocationName, resource group $ResourceGroupName, HyperVGeneration $HyperVGeneration, helper VM size $HelperVMSize, image $ImageName"


$VentoyBashScript=
@'
#!/bin/bash
# Runs as root inside the Linux helper VM (Azure CustomScript extension).
# Turns the data disk on lun 1 into a Ventoy disk containing the Photon OS iso, configured for the Azure serial console.
set -euo pipefail

URI='__URI__'
ISO_NAME='__ISO_NAME__'
ISO_SHA256='__ISO_SHA256__'
ISO_SHA256_URL='__ISO_SHA256_URL__'
ARCHITECTURE='__ARCHITECTURE__'
HYPERV_GENERATION='__HYPERV_GENERATION__'
VENTOY_VERSION='__VENTOY_VERSION__'
VENTOY_SHA256='__VENTOY_SHA256__'
DISK_SIZE_GB='__DISK_SIZE_GB__'

echo "== Locating the data disk on lun 1"
DISK=""
for link in /dev/disk/azure/scsi1/lun1 /dev/disk/azure/data/by-lun/1; do
    if [ -e "$link" ]; then DISK=$(readlink -f "$link"); break; fi
done
if [ -z "$DISK" ]; then
    WANT_BYTES=$((DISK_SIZE_GB * 1024 * 1024 * 1024))
    DISK=$(lsblk -dnbpo NAME,SIZE,TYPE | awk -v want="$WANT_BYTES" '$3 == "disk" && $2 == want { print $1; exit }')
fi
if [ -z "$DISK" ] || [ ! -b "$DISK" ]; then echo "Data disk not found."; lsblk; exit 1; fi
ROOT_DISK=$(lsblk -npo PKNAME "$(findmnt -nvo SOURCE /)")
if [ "$DISK" = "$ROOT_DISK" ]; then echo "Refusing to use $DISK, it is the OS disk."; exit 1; fi
if lsblk -no MOUNTPOINT "$DISK" | grep -q '[^[:space:]]'; then echo "Refusing to use $DISK, it has mounted partitions."; exit 1; fi
echo "Using $DISK"

echo "== Installing prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq parted dosfstools curl >/dev/null

echo "== Installing Ventoy $VENTOY_VERSION"
WORK_DIR=/opt/ventoy
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
curl -fsSL --retry 5 -o ventoy.tar.gz "https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz"
if [ -n "$VENTOY_SHA256" ]; then echo "$VENTOY_SHA256  ventoy.tar.gz" | sha256sum -c -; fi
tar -xzf ventoy.tar.gz
cd "ventoy-${VENTOY_VERSION}"
PARTITION_STYLE=""
if [ "$HYPERV_GENERATION" = "V2" ]; then PARTITION_STYLE="-g"; fi
# Ventoy2Disk asks twice for confirmation and exits 0 when not confirmed, hence the check with -l
printf 'y\ny\n' | sh ./Ventoy2Disk.sh -I $PARTITION_STYLE "$DISK"
sh ./Ventoy2Disk.sh -l "$DISK" | tee /tmp/ventoy-list.txt
grep -q "Ventoy Version in Disk" /tmp/ventoy-list.txt || { echo "Ventoy installation failed."; exit 1; }

udevadm settle
partprobe "$DISK" || true
sleep 3
PART1=$(lsblk -lnpo NAME,TYPE "$DISK" | awk '$2 == "part" { print $1; exit }')
if [ -z "$PART1" ] || [ ! -b "$PART1" ]; then echo "Ventoy partition not found."; lsblk "$DISK"; exit 1; fi

echo "== Mounting the Ventoy exFAT partition $PART1"
mkdir -p /mnt/ventoy /mnt/iso
# The Ubuntu azure kernel ships the exfat module in linux-modules-extra only, exfat-fuse is the fallback.
if ! grep -qw exfat /proc/filesystems && ! modprobe exfat 2>/dev/null; then
    apt-get install -y -qq "linux-modules-extra-$(uname -r)" >/dev/null 2>&1 && modprobe exfat 2>/dev/null || true
fi
if grep -qw exfat /proc/filesystems; then
    mount -t exfat "$PART1" /mnt/ventoy
else
    echo "exfat kernel module not available, using exfat-fuse"
    apt-get install -y -qq exfat-fuse >/dev/null
    mount.exfat-fuse "$PART1" /mnt/ventoy
fi

# The url is not printed, it may contain a SAS token.
echo "== Downloading $ISO_NAME"
curl -fsSL --retry 5 --retry-delay 10 -o "/mnt/ventoy/$ISO_NAME" "$URI"
if [ -z "$ISO_SHA256" ] && [ -n "$ISO_SHA256_URL" ]; then
    ISO_SHA256=$(curl -fsSL "$ISO_SHA256_URL" 2>/dev/null | awk '{ print $1 }' || true)
fi
if [ -n "$ISO_SHA256" ]; then
    echo "$ISO_SHA256  /mnt/ventoy/$ISO_NAME" | sha256sum -c -
else
    echo "No sha256 available, checksum not verified."
fi

echo "== Boot configuration for the Azure serial console"
mount -o loop,ro "/mnt/ventoy/$ISO_NAME" /mnt/iso
mkdir -p /mnt/ventoy/ventoy
cp /mnt/iso/boot/grub2/grub.cfg /mnt/ventoy/ventoy/grub.cfg
HAS_MENU_CFG=0
if [ "$ARCHITECTURE" = "x64" ] && [ -f /mnt/iso/isolinux/menu.cfg ]; then
    cp /mnt/iso/isolinux/menu.cfg /mnt/ventoy/ventoy/menu.cfg
    HAS_MENU_CFG=1
fi
umount /mnt/iso

GRUB_CFG=/mnt/ventoy/ventoy/grub.cfg
# Exactly one console= parameter: the installer initrd starts photon-installer only on the tty matching
# /sys/devices/virtual/tty/console/active, which lists all consoles (e.g. "tty1 ttyAMA0" never matches).
if [ "$ARCHITECTURE" = "Arm64" ]; then
    # Azure Arm64 VMs expose the serial console as PL011 uart ttyAMA0
    KERNEL_CONSOLE="console=ttyAMA0,115200 earlycon"
    sed -i -E 's/^[[:space:]]*terminal_output[[:space:]]+gfxterm[[:space:]]*$/terminal_output console/' "$GRUB_CFG"
else
    KERNEL_CONSOLE="console=ttyS0,115200n8 earlyprintk=ttyS0,115200"
    sed -i -E 's/^[[:space:]]*terminal_output[[:space:]]+gfxterm[[:space:]]*$/serial --unit=0 --speed=115200\nterminal_input serial console\nterminal_output serial console/' "$GRUB_CFG"
fi
sed -i -E "s/^([[:space:]]*linux[[:space:]].*)\$/\1 ${KERNEL_CONSOLE}/" "$GRUB_CFG"
grep -qF "$KERNEL_CONSOLE" "$GRUB_CFG" || { echo "No linux line found in grub.cfg."; cat "$GRUB_CFG"; exit 1; }
if [ "$HAS_MENU_CFG" = "1" ]; then
    sed -i -E "s/^([[:space:]]*append[[:space:]].*)\$/\1 console=ttyS0,115200n8/" /mnt/ventoy/ventoy/menu.cfg
fi

if [ "$ARCHITECTURE" = "Arm64" ]; then
    THEME='"display_mode": "CLI"'
else
    THEME='"display_mode": "serial_console", "serial_param": "--unit=0 --speed=115200"'
fi
MENU_CFG_REPLACE=""
if [ "$HAS_MENU_CFG" = "1" ]; then
    MENU_CFG_REPLACE=", { \"iso\": \"/$ISO_NAME\", \"org\": \"/isolinux/menu.cfg\", \"new\": \"/ventoy/menu.cfg\" }"
fi
# conf_replace org paths must match the files inside the iso: /boot/grub2/grub.cfg (UEFI) and /isolinux/menu.cfg (legacy BIOS)
cat > /mnt/ventoy/ventoy/ventoy.json <<EOF
{
    "control": [
        { "VTOY_DEFAULT_IMAGE": "/$ISO_NAME" },
        { "VTOY_MENU_TIMEOUT": "5" },
        { "VTOY_SECONDARY_BOOT_MENU": "0" }
    ],
    "theme": { $THEME },
    "conf_replace": [
        { "iso": "/$ISO_NAME", "org": "/boot/grub2/grub.cfg", "new": "/ventoy/grub.cfg" }$MENU_CFG_REPLACE
    ]
}
EOF
python3 -m json.tool /mnt/ventoy/ventoy/ventoy.json
cat "$GRUB_CFG"

sync
umount /mnt/ventoy
echo "PHOTON_VENTOY_OK"
'@


$Scriptrun=
@'

# Runs inside the Windows helper VM: the Photon OS vhd file bits are downloaded, extracted and uploaded as page blob for generating the Azure image.

$PSDefaultParameterValues = @{ 'out-file:encoding' = 'ascii' }
$IsVhdUploaded=$env:public + [IO.Path]::DirectorySeparatorChar + "VhdUploaded.txt"
# $Uri may be a SAS url of a temporary blob, hence the file name is passed separately
$tmpfilename=$FileName
# e.g. photon-azure-5.0-dde71ec57.x86_64.vhd.tar.gz contains photon-azure-5.0-dde71ec57.x86_64.vhd
$tmpname=($tmpfilename -split [regex]::Escape(".vhd"))[0] + ".vhd"
$vhdfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpname
$downloadfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpfilename


#
#   A) The script is started in localsystem account. In LocalSystem context there is no possibility to connect outside.
#      Hence, the script creates a run once scheduled task with user impersonation and executing the downloaded powershell script.
#      There are some hacks in localsystem context to make a run-once-scheduled task with user logon type.
#   B) Portion of the script uses Azure Powershell.
#

if ($env:username -ine $HelperVMLocalAdminUser)
{
    $filetostart=$MyInvocation.MyCommand.Source
    $LocalUser=$HelperVMLocalAdminUser

	$PowershellFilePath =  "$PsHome\powershell.exe"
    $Taskname = "PhotonProcessing"
	$Argument = "\"""+$PowershellFilePath +"\"" -WindowStyle Hidden -NoLogo -NoProfile -Executionpolicy unrestricted -command \"""+$filetostart+"\"""

    schtasks.exe /create /F /TN "$Taskname" /tr $Argument /SC ONCE /ST 00:00 /RU ${LocalUser} /RP ${HelperVMLocalAdminPwd} /RL HIGHEST /NP
    start-sleep -s 1
    schtasks /Run /TN "$Taskname" /I

    # Scheduled task run takes time. The custom script extension times out after 90 minutes.
    $timeout=(get-date).AddMinutes(85)
    do { start-sleep -s 5 } until ((test-path(${IsVhdUploaded})) -or ((get-date) -gt $timeout))
    exit
}


# Extract and import the cached azcontext
$orgfile=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext.txt"
$fileencoded=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext_encoded.txt"
if ((test-path($fileencoded)) -eq $false)
{
	out-file -inputobject $CachedAzContext -FilePath $fileencoded
	if ((test-path($orgfile)) -eq $true) {remove-item -path ($orgfile) -force}
	certutil -decode $fileencoded $orgfile
	if ((test-path($orgfile)) -eq $true)
    {
        import-azcontext -path $orgfile
        remove-item -path ($fileencoded) -force
        remove-item -path ($orgfile) -force
    }
}

if (Test-Path -d $tmppath)
{
    if (!(Test-Path $downloadfile))
    {
        cd $tmppath
        $RootDrive="'"+$(split-path -path $tmppath -Qualifier)+"'"
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID=$RootDrive" | select-object @{Name="FreeGB";Expression={[math]::Round($_.Freespace/1GB,2)}}
        if ($disk.FreeGB -gt 20)
        {
            install-module PS7Zip -force

            if (!(Test-Path $vhdfile))
            {
                c:\windows\system32\curl.exe -L -o $tmpfilename $Uri
            }
            if ((Test-Path $downloadfile) -and ((([IO.Path]::GetExtension($tmpfilename)) -ieq ".gz")))
            {
                try
                {
                    $PatchCheck=$tmppath + [io.path]::DirectorySeparatorChar+"photon-azure-3.0-49fd219.vhd.tar.gz"
                    if ($downloadfile -ieq $PatchCheck)
                    {
                         $PatchDir = $tmppath + [io.path]::DirectorySeparatorChar+ "root" + [io.path]::DirectorySeparatorChar+ "photon" + [io.path]::DirectorySeparatorChar+ "stage" + [io.path]::DirectorySeparatorChar+ "azure"
                         mkdir $PatchDir
                         $vhdfile=$PatchDir + [io.path]::DirectorySeparatorChar+$tmpname
                    }
                    c:\windows\system32\tar.exe -xzvf $downloadfile
                }
                catch{}
                if (!(Test-Path $vhdfile))
                {
                        # Windows tar does not extract photon-azure-2.0-304b817.vhd.gz but PS7Zip does.
                        # work directory must be path of $tmpfilename
                        Expand-7Zip -FullName $tmpfilename -destinationpath $tmpname -ErrorAction SilentlyContinue
                        # vhdfile should now be unextracted into directory $tmpname
                        $vhdfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpname + [io.path]::DirectorySeparatorChar + $tmpname
                }
            }
        }
    }

    if (Test-Path $vhdfile)
    {
	    $azcontext=get-azcontext
	    if ($azcontext)
	    {
		    $storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
		    if ($storageaccount)
		    {
                $result=get-azstorageblob -Container ${HelperVMContainerName} -Blob ${ImageName} -Context $storageaccount.Context -ErrorAction SilentlyContinue
                if ( -not ($result))
			    {
                    Set-AzStorageBlobContent -Container ${HelperVMContainerName} -File $vhdfile -Blob ${ImageName} -BlobType page -Context $storageaccount.Context
			    }
                $result=get-azstorageblob -Container ${HelperVMContainerName} -Blob ${ImageName} -Context $storageaccount.Context -ErrorAction SilentlyContinue
                if ($result)
			    {
                    $vhdfile | out-file -filepath $IsVhdUploaded -append
                }
		    }
	    }
    }
}

'@


if ($IsIso)
{
    $existingVersion = Get-AzResourceOrNull { Get-AzGalleryImageVersion -ResourceGroupName $ResourceGroupName -GalleryName $GalleryName -GalleryImageDefinitionName $ImageName -Name $ImageVersion }
    if ($existingVersion)
    {
        write-output "Image $ImageName version $ImageVersion already exists in gallery ${GalleryName}: $($existingVersion.Id)"
        return
    }

    $capacity = Test-HelperVMCapacity -Location $LocationName -VMSize $HelperVMSize
    if ($capacity.HyperVGenerations -notmatch 'V2') { throw "Helper VM size $HelperVMSize does not support HyperVGeneration V2." }
    if (-not (Get-AzResourceOrNull { Get-AzResourceGroup -Name $ResourceGroupName })) { $null = New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName }
    $HelperVMPublisherName = "Canonical"
    $HelperVMofferName = "0001-com-ubuntu-server-jammy"
    if ($capacity.Architecture -eq 'Arm64') { $HelperVMsku = "22_04-lts-arm64" } else { $HelperVMsku = "22_04-lts-gen2" }

    $ImageCreated = $false
    try
    {
        if ($IsLocalFile)
        {
            write-output "Computing SHA256 of $($LocalFile.FullName) ..."
            $IsoSha256 = (Get-FileHash -LiteralPath $LocalFile.FullName -Algorithm SHA256).Hash.ToLower()
            $IsoSha256Url = ''
            write-output "Uploading $DownloadFileName ($([math]::Round($LocalFile.Length / 1GB, 2)) GB) to the temporary blob container $SourceContainerName of storage account $StorageAccountName ..."
            $Uri = Publish-LocalFile
        }
        else
        {
            $IsoSha256 = ''
            $IsoSha256Url = "$Uri.sha256"
        }

        # The empty data disk becomes the bootable Ventoy disk and later the image source.
        write-output "Creating data disk $HelperVMDataDiskName ..."
        $diskConfig = New-AzDiskConfig -Location $LocationName -CreateOption Empty -DiskSizeGB $HelperVMDiskSizeGB -SkuName StandardSSD_LRS -OsType Linux -HyperVGeneration $HyperVGeneration -Architecture $Architecture
        $Disk = New-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $HelperVMDataDiskName -Disk $diskConfig

        write-output "Creating helper VM $HelperVMName ($HelperVMSize, Ubuntu $HelperVMsku) ..."
        $nic = New-HelperVMNetwork
        $LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($HelperVMLocalAdminUser, (ConvertTo-SecureString $HelperVMLocalAdminPwd -AsPlainText -Force))
        $vmConfig = New-AzVMConfig -VMName $HelperVMName -VMSize $HelperVMSize
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $HelperVMComputerName -Credential $LocalAdminUserCredential
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku -Version latest
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -CreateOption FromImage -StorageAccountType StandardSSD_LRS
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        $vmConfig = Add-AzVMDataDisk -VM $vmConfig -ManagedDiskId $Disk.Id -Name $HelperVMDataDiskName -Lun 1 -CreateOption Attach
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable
        $null = New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig

        write-output "Preparing the Ventoy disk inside the helper VM. Downloading $DownloadFileName takes a while ..."
        $bash = $VentoyBashScript.Replace("`r`n", "`n").
            Replace('__URI__', $Uri).
            Replace('__ISO_NAME__', $DownloadFileName).
            Replace('__ISO_SHA256_URL__', $IsoSha256Url).
            Replace('__ISO_SHA256__', $IsoSha256).
            Replace('__ARCHITECTURE__', $Architecture).
            Replace('__HYPERV_GENERATION__', $HyperVGeneration).
            Replace('__VENTOY_VERSION__', $VentoyVersion).
            Replace('__VENTOY_SHA256__', [string]$VentoySha256).
            Replace('__DISK_SIZE_GB__', [string]$HelperVMDiskSizeGB)
        $ProtectedSettings = @{ "script" = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash)) }
        $extensionError = $null
        try
        {
            $null = Set-AzVMExtension -ResourceGroupName $ResourceGroupName -Location $LocationName -VMName $HelperVMName -Name "PhotonOSVentoy" -Publisher "Microsoft.Azure.Extensions" -ExtensionType "CustomScript" -TypeHandlerVersion "2.1" -ProtectedSettings $ProtectedSettings
        }
        catch { $extensionError = $_.Exception.Message }
        # The bash script runs with set -e, a failure surfaces as extension error. The stdout/stderr substatuses are informational.
        $extension = Get-AzResourceOrNull { Get-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $HelperVMName -Name "PhotonOSVentoy" -Status }
        $substatuses = @($extension.SubStatuses) + @($extension.InstanceView.Substatuses)
        if (-not ($substatuses | Where-Object { $_ }))
        {
            $vmStatus = Get-AzResourceOrNull { Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName -Status }
            $substatuses = @(($vmStatus.Extensions | Where-Object { $_.Name -eq 'PhotonOSVentoy' }).Substatuses)
        }
        $extensionOutput = ($substatuses | Where-Object { $_ } | ForEach-Object { $_.Message }) -join "`n"
        if ($extensionOutput) { write-output $extensionOutput }
        if ($extensionError)
        {
            throw "Preparing the Ventoy disk failed. $extensionError"
        }
        if ($extensionOutput -and ($extensionOutput -notmatch 'PHOTON_VENTOY_OK'))
        {
            throw "Preparing the Ventoy disk did not complete."
        }
        if (-not $extensionOutput) { Write-Warning "The extension output is not available, relying on the extension status Succeeded." }

        write-output "Detaching data disk $HelperVMDataDiskName ..."
        $null = Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName -Force
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName
        $null = Remove-AzVMDataDisk -VM $vm -DataDiskNames $HelperVMDataDiskName
        $null = Update-AzVM -ResourceGroupName $ResourceGroupName -VM $vm
        $i = 0
        do
        {
            start-sleep -Seconds 5
            $Disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $HelperVMDataDiskName
            $i++
        }
        until (($Disk.DiskState -ieq 'Unattached') -or ($i -gt 60))
        if ($Disk.DiskState -ine 'Unattached') { throw "Data disk $HelperVMDataDiskName is still $($Disk.DiskState)." }

        $gallery = Get-AzResourceOrNull { Get-AzGallery -ResourceGroupName $ResourceGroupName -Name $GalleryName }
        if (-not $gallery)
        {
            write-output "Creating Azure Compute Gallery $GalleryName ..."
            $gallery = New-AzGallery -ResourceGroupName $ResourceGroupName -Name $GalleryName -Location $LocationName -Description "VMware Photon OS images"
        }
        $definition = Get-AzResourceOrNull { Get-AzGalleryImageDefinition -ResourceGroupName $ResourceGroupName -GalleryName $GalleryName -Name $ImageName }
        if (-not $definition)
        {
            # Specialized: the Photon OS installer has no Azure provisioning agent, hence a VM from this image must not have an OS profile.
            $definition = New-AzGalleryImageDefinition -ResourceGroupName $ResourceGroupName -GalleryName $GalleryName -Name $ImageName -Location $LocationName `
                -Publisher "PhotonOS" -Offer ("photon-" + ($ImageVersion -replace '\.0$', '')) -Sku (Get-AzSafeName -Name $ImageName -MaxLength 64) `
                -OsState Specialized -OsType Linux -HyperVGeneration $HyperVGeneration -Architecture $Architecture `
                -Description "VMware Photon OS installer $DownloadFileName on a Ventoy disk"
        }

        write-output "Creating image version $ImageVersion of $ImageName. This takes a few minutes ..."
        $imageVersionObject = New-AzGalleryImageVersion -ResourceGroupName $ResourceGroupName -GalleryName $GalleryName -GalleryImageDefinitionName $ImageName -Name $ImageVersion -Location $LocationName `
            -OSDiskImage @{ Source = @{ Id = $Disk.Id } } -TargetRegion @(@{ Name = $LocationName; ReplicaCount = 1 })
        $ImageCreated = $true
        write-output "Image created: $($imageVersionObject.Id)"
    }
    finally
    {
        if ($SkipCleanup) { write-output "SkipCleanup: the helper VM $HelperVMName and its resources are kept." }
        else
        {
            write-output "Removing helper resources ..."
            Remove-HelperVMResources
        }
        Remove-TemporarySourceBlob
        if (-not $ImageCreated) { write-output "Error: Image creation failed." }
    }
}
else
{
    $existingImage = Get-AzResourceOrNull { Get-AzImage -ResourceGroupName $ResourceGroupName -ImageName $ImageName }
    if ($existingImage)
    {
        write-output "Image $ImageName already exists: $($existingImage.Id)"
        return
    }

    $capacity = Test-HelperVMCapacity -Location $LocationName -VMSize $HelperVMSize
    if ($capacity.Architecture -eq 'Arm64') { throw "Vhd files are processed on a Windows helper VM. Specify an x64 -HelperVMSize." }
    if ($capacity.TempDiskMB -lt 20480) { throw "Vhd files are extracted on the temporary disk of the helper VM. $HelperVMSize has no or a too small temporary disk, e.g. use Standard_E2s_v3." }
    if (-not (Get-AzResourceOrNull { Get-AzResourceGroup -Name $ResourceGroupName })) { $null = New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName }
    $HelperVMPublisherName = "MicrosoftWindowsServer"
    $HelperVMofferName = "WindowsServer"
    $HelperVMsku = "2022-datacenter-core-smalldisk-g2"

    $ImageCreated = $false
    $contextfile = $($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext.txt"
    $ScriptFile = $($env:public) + [IO.Path]::DirectorySeparatorChar + "importazcontext.ps1"
    $Blobtmp = "importazcontext.ps1"
    try
    {
        # storageaccount with a private container
        $storageaccount = Get-AzResourceOrNull { Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName }
        if (-not $storageaccount)
        {
            $storageaccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind $StorageKind -SkuName $StorageAccountType -AllowBlobPublicAccess $false -MinimumTlsVersion TLS1_2
        }
        do {start-sleep -Milliseconds 1000} until ($((get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).ProvisioningState) -ieq "Succeeded")
        $storageaccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
        $storageaccountkey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
        if (-not (Get-AzResourceOrNull { Get-AzStorageContainer -Name $HelperVMContainerName -Context $storageaccount.Context }))
        {
            $null = New-AzStorageContainer -Name $HelperVMContainerName -Context $storageaccount.Context -Permission Off
        }

        if ($IsLocalFile)
        {
            write-output "Uploading $DownloadFileName ($([math]::Round($LocalFile.Length / 1GB, 2)) GB) to the temporary blob container $SourceContainerName of storage account $StorageAccountName ..."
            $Uri = Publish-LocalFile
        }

        write-output "Creating helper VM $HelperVMName ($HelperVMSize, Windows Server 2022) ..."
        $nic = New-HelperVMNetwork
        $LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($HelperVMLocalAdminUser, (ConvertTo-SecureString $HelperVMLocalAdminPwd -AsPlainText -Force))
        $vmConfig = New-AzVMConfig -VMName $HelperVMName -VMSize $HelperVMSize
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $HelperVMComputerName -Credential $LocalAdminUserCredential
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku -Version latest
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable
        $null = New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig

        # Prepare scriptfile
        $null = Save-AzContext -Path $contextfile -Force
        $contextfileEncoded=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext_enc.txt"
        if ((test-path($contextfileEncoded)) -eq $true) {remove-item -path ($contextfileEncoded) -force}
        $null = certutil -encode $contextfile $contextfileEncoded
        $content = get-content -path $contextfileEncoded
        $value = '$CachedAzContext=@'+"'`r`n"
        # https://stackoverflow.com/questions/42407136/difference-between-redirection-to-null-and-out-null
        $null = new-item $ScriptFile -type file -force -value $value
        out-file -inputobject $content -FilePath $ScriptFile -Encoding ASCII -Append
        out-file -inputobject "'@" -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='$Uri="'+$Uri+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='$FileName="'+$DownloadFileName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='$tmppath="'+$HelperVMsize_TempPath+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='$ResourceGroupName="'+$ResourceGroupName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='$StorageAccountName="'+$StorageAccountName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='$ImageName="'+$ImageName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='$HelperVMContainerName="'+$HelperVMContainerName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='$HelperVMLocalAdminUser="'+$HelperVMLocalAdminUser+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='$HelperVMLocalAdminPwd="'+$HelperVMLocalAdminPwd+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        out-file -inputobject $ScriptRun -FilePath $ScriptFile -Encoding ASCII -append
        remove-item -path ($contextfileEncoded) -force

        # blob upload of scriptfile
        $null = Set-AzStorageBlobContent -Container ${HelperVMContainerName} -File $ScriptFile -Blob ${BlobTmp} -BlobType Block -Context $storageaccount.Context -Force

        # Remote install Az module
        $Extensions = Get-AzVMExtensionImage -Location $LocationName -PublisherName "Microsoft.Compute" -Type "CustomScriptExtension"
        $ExtensionPublisher= $Extensions[$Extensions.count-1].PublisherName
        $ExtensionType = $Extensions[$Extensions.count-1].Type
        $ExtensionVersion = (($Extensions[$Extensions.count-1].Version) -split '\.')[0..1] -join "."
        $commandToExecute="powershell.exe Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force ; powershell install-module -name Az -force -ErrorAction SilentlyContinue; shutdown.exe /r /t 0"
        $ProtectedSettings = @{"commandToExecute" = $commandToExecute }
        try
        {
            $null = Set-AzVMExtension -ResourceGroupName $ResourceGroupName -Location $LocationName -VMName $HelperVMName -Name $ExtensionType -Publisher $ExtensionPublisher -ExtensionType $ExtensionType -TypeHandlerVersion $ExtensionVersion -Settings @{} -ProtectedSettings $ProtectedSettings
        }
        catch { Write-Warning "Az module installation reported: $($_.Exception.Message)" }
        $null = Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $HelperVMName -Name $ExtensionType -Force -ErrorAction SilentlyContinue
        # wait for the reboot
        start-sleep 60

        # Run scriptfile
        write-output "Downloading and uploading the Photon OS vhd inside the helper VM. This takes a while ..."
        $null = Set-AzVMCustomScriptExtension -Name "CustomScriptExtension" -Location $LocationName -ResourceGroupName $ResourceGroupName -VMName $HelperVMName -StorageAccountName $StorageAccountName -StorageAccountKey $storageaccountkey -ContainerName $HelperVMContainerName -FileName $BlobTmp -Run $BlobTmp
        # the scriptfile contains the cached azcontext
        $null = Remove-AzStorageBlob -Container $HelperVMContainerName -Blob $BlobTmp -Context $storageaccount.Context -Force

        if (-not (Get-AzResourceOrNull { Get-AzStorageBlob -Container $HelperVMContainerName -Blob $ImageName -Context $storageaccount.Context }))
        {
            throw "The vhd blob $ImageName has not been uploaded."
        }

        write-output "Creating image $ImageName ..."
        $urlOfUploadedVhd = $storageaccount.PrimaryEndpoints.Blob + "${HelperVMContainerName}/${ImageName}"
        $diskConfig = New-AzDiskConfig -SkuName $StorageAccountType -Location $LocationName -HyperVGeneration $HyperVGeneration -OsType Linux -CreateOption Import -StorageAccountId $storageaccount.Id -SourceUri $urlOfUploadedVhd
        $ImportedDisk = New-AzDisk -Disk $diskConfig -ResourceGroupName $ResourceGroupName -DiskName $HelperVMDataDiskName
        $imageConfig = New-AzImageConfig -Location $LocationName -HyperVGeneration $HyperVGeneration
        $imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsState Generalized -OsType Linux -ManagedDiskId $ImportedDisk.Id
        $image = New-AzImage -ImageName $ImageName -ResourceGroupName $ResourceGroupName -Image $imageConfig
        $ImageCreated = $true
        write-output "Image created: $($image.Id)"
    }
    finally
    {
        foreach ($file in @($contextfile, $ScriptFile)) { if (test-path $file) { remove-item -path $file -force -ErrorAction SilentlyContinue } }
        Remove-TemporarySourceBlob
        if ($SkipCleanup) { write-output "SkipCleanup: the helper VM $HelperVMName, its resources and storage account $StorageAccountName are kept." }
        else
        {
            write-output "Removing helper resources ..."
            Remove-HelperVMResources
            try
            {
                if (Get-AzResourceOrNull { Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName })
                {
                    $null = Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force
                }
            }
            catch { Write-Warning "Cleanup of storage account $StorageAccountName failed: $($_.Exception.Message)" }
        }
        if (-not $ImageCreated) { write-output "Error: Image creation failed." }
    }
}
