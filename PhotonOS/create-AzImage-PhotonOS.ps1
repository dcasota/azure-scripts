# .SYNOPSIS
#  Deploy an Azure image of VMware Photon OS
#
# .DESCRIPTION
#  VMware Photon OS comes with multi-cloud support, use-case centric flavors, x86_64 and arm64 support and it supports virtual hardware generations.
#  On Azure actually, there are no official VMware Photon OS images. This may change. For the moment, this helper script deploys an Azure image of Photon OS.
#
#  It creates an Azure image of VMware Photon OS by iso or vhd download url. Url, location and the resource group name as mandatory parameters.
#  Without specifying further parameters, an Azure image Hyper-V generation V2 is created.
#  The name of the Azure image is adopted from the download url and the HyperVGeneration ending _V1.vhd or _V2.vhd. It looks like "photon-azure-4.0-c001795b8_V2.vhd" or "photon-azure-4.0-c001795b8_iso_V2.vhd".
#
#  First, the script installs the Az 8.0 module, if necessary, and triggers an Azure login using the device code method. You might see a similar message to
#    WARNUNG: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxxx to authenticate.
#  The Azure Powershell output shows up as warning (see above). Open a webbrowser, and fill in the code given by the Azure Powershell login output.
#
#  A temporary Azure windows virtual machine is created with Microsoft Windows Server 2022 on a specifiable Hyper-V generation virtual hardware V1/V2 using an appropriate Azure offering.
#  See Azure virtual hardware generation related weblink https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2
#  In case of an iso, the added disk is Ventoy-configured, stores the Photon OS iso file and converted to vhd using disk2vhd.
#  After uploading the Photon OS vhd file as Azure page blob, the Azure Photon OS image is created. The cleanup deletes the temporary virtual machine.
#
#  .PREREQUISITES
#    - Script must run on MS Windows OS with Powershell PSVersion 5.1 or higher
#    - Azure account with Virtual Machine contributor role
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
#
# .PARAMETER DownloadURL
#   Specifies the URL of the VMware Photon OS .iso file
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

#   Specifies the URL of the VMware Photon OS .vhd.tar.gz file
#      VMware Photon OS build download links:
#        Photon OS 4.0 Rev2 Azure VHD                        https://packages.vmware.com/photon/4.0/Rev2/azure/photon-azure-4.0-c001795b8.vhd.tar.gz
#        Photon OS 4.0 Rev1 Azure VHD                        https://packages.vmware.com/photon/4.0/Rev1/azure/photon-azure-4.0-ca7c9e933.vhd.tar.gz
#        Photon OS 4.0 GA Azure VHD                          https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz
#        Photon OS 4.0 RC Azure VHD                          https://packages.vmware.com/photon/4.0/RC/azure/photon-azure-4.0-a3a49f540.vhd.tar.gz
#        Photon OS 4.0 Beta Azure VHD                        https://packages.vmware.com/photon/4.0/Beta/azure/photon-azure-4.0-d98e681.vhd.tar.gz
#        Photon OS 3.0 Revision 2 Azure VHD                  https://packages.vmware.com/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz
#        Photon OS 3.0 GA Azure VHD                          https://packages.vmware.com/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz
#        Photon OS 3.0 RC Azure VHD                          https://packages.vmware.com/photon/3.0/RC/azure/photon-azure-3.0-49fd219.vhd.tar.gz
#        Photon OS 3.0 Beta                                  https://packages.vmware.com/photon/3.0/Beta/azure/photon-azure-3.0-5e45dc9.vhd.tar.gz
#        Photon OS 2.0 GA Azure VHD gz file:                 https://packatares.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-304b817.vhd.gz
#        Photon OS 2.0 GA Azure VHD cloud-init provisioning  https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-3146fa6.tar.gz
#        Photon OS 2.0 RC Azure VHD - gz file                https://packages.vmware.com/photon/2.0/RC/azure/photon-azure-2.0-31bb961.vhd.gz
#        Photon OS 2.0 Beta Azure VHD                        https://packages.vmware.com/photon/2.0/Beta/azure/photon-azure-2.0-8553d58.vhd
# .PARAMETER LocationName
#   Azure location name where to create or lookup the resource group
# .PARAMETER ResourceGroupName
#   resource group name
# .PARAMETER RuntimeId
#   random id used in names
# .PARAMETER StorageAccountName
#   storage account name
# .PARAMETER StorageKind
#   storage kind
# .PARAMETER StorageAccountType
#   storage account type
# .PARAMETER HyperVGeneration
#   Azure HyperVGeneration
#
# .EXAMPLE
#    ./create-AzImage-PhotonOS.ps1 -DownloadURL "https://packages.vmware.com/photon/4.0/Rev2/iso/photon-4.0-c001795b8.iso" -ResourceGroupName PhotonOSTemplates -LocationName switzerlandnorth -HyperVGeneration V2
#
#>

[CmdletBinding()]
param(
[Parameter(Mandatory = $true)][ValidateNotNull()]
[ValidateSet(`
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
[String]$DownloadURL="https://packages.vmware.com/photon/4.0/Rev2/iso/photon-4.0-c001795b8.iso",

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$LocationName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupName,

[Parameter(Mandatory = $false)]
[string]$RuntimeId = (Get-Random).ToString(),

[Parameter(Mandatory = $false)][ValidateLength(3,24)][ValidatePattern("[a-z0-9]")]
[string]$StorageAccountName=("PhotonOS${RuntimeId}").ToLower(),

[Parameter(Mandatory = $false)]
[string]$StorageKind="Storage",

[Parameter(Mandatory = $false)]
[string]$StorageAccountType="Standard_LRS",

[Parameter(Mandatory = $false)][ValidateSet('V1','V2')]
[string]$HyperVGeneration="V2"

)


if ($DownloadURL.ToLower().EndsWith('.iso'))
{
    # Imagename is a .vhd file, generated using Ventoy with included Photon OS iso file
    [string]$ImageName=$(((split-path -path $([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($DownloadURL)) -Leaf) -split ".iso")[0] + "_iso_" + $HyperVGeneration + ".vhd")
    # Uri + Blobname
    $Uri=$([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($DownloadURL))
    $BlobName=((split-path -path $Uri -Leaf) -split ".iso")[0] + ".iso"
}
else
{
   [string]$ImageName=$(((split-path -path $([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($DownloadURL)) -Leaf) -split ".vhd")[0] + "_" + $HyperVGeneration + ".vhd")
    # Uri + Blobname
    $Uri=$([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($DownloadURL))
    $BlobName=((split-path -path $Uri -Leaf) -split ".vhd")[0] + ".vhd"
}


# HelperVM settings
$HelperVMComputerName = "w2k22${RuntimeId}"
$HelperVMName = $HelperVMComputerName
$HelperVMContainerName = "${HelperVMComputerName}disks"
$HelperVMDiskName="${HelperVMComputerName}PhotonOSDisk"
$HelperVMDiskSizeGB='16'
if (($DownloadURL.ToLower().EndsWith('-aarch64.iso')) -or ($DownloadURL.ToLower().EndsWith('-aarch64.tar.gz')))
{
    # Not fully implemented yet !
    $HelperVMPublisherName = "Canonical"
    $HelperVMofferName = "0001-com-ubuntu-server-jammy"
    $HelperVMsku = "22_04-lts-arm64"
    $HelperVMsize="Standard_D32plds_v5"
    $HelperVMsize_TempPath="/dev/sdb" # $DownloadURL file is downloaded and extracted on this drive inside vm. Depending of the VMSize offer, it includes built-in an additional non persistent  drive.
}
else
{
    $HelperVMPublisherName = "MicrosoftWindowsServer"
    $HelperVMofferName = "WindowsServer"
    $HelperVMsku = "2022-datacenter-core-smalldisk-g2"
    $HelperVMsize="Standard_E4s_v3"
    $HelperVMsize_TempPath="d:" # $DownloadURL file is downloaded and extracted on this drive inside vm. Depending of the VMSize offer, it includes built-in an additional non persistent  drive.
}
$HelperVMNetworkName = "${HelperVMComputerName}vnet"
$HelperVMSubnetAddressPrefix = "192.168.1.0/24"
$HelperVMVnetAddressPrefix = "192.168.0.0/16"
$HelperVMnsgName = "${HelperVMComputerName}nsg"
$HelperVMPublicIPDNSName="${HelperVMComputerName}dns"
$HelperVMNICName = "${HelperVMComputerName}nic"
$HelperVMLocalAdminUser = "LocalAdminUser"
$HelperVMLocalAdminPwd="Secure2020123!" #12-123 chars




# Specify Tls
$TLSProtocols = [System.Net.SecurityProtocolType]::'Tls13',[System.Net.SecurityProtocolType]::'Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $TLSProtocols

# Check Azure Powershell
try
{
	# $version = (get-installedmodule -name Az).version # really slow
    $version = (get-command get-azcontext).Version.ToString()
	if ($version -lt "2.8")
	{
		write-output "Updating Azure Powershell ..."	
		update-module -Name Az -RequiredVersion "8.0" -ErrorAction SilentlyContinue
		write-output "Please restart Powershell session."
		break			
	}
}
catch
{
    write-output "Installing Azure Powershell ..."
    install-module -Name Az -RequiredVersion "8.0" -ErrorAction SilentlyContinue
    write-output "Please restart Powershell session."
    break	
}

$azconnect=$null
try
{
    # Already logged-in?
    $subscriptionId=(get-azcontext).Subscription.Id
    $TenantId=(get-azcontext).Tenant.Id
    # set subscription
    select-AzSubscription -Subscription $subscriptionId -tenant $TenantId -ErrorAction Stop
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
        select-AzSubscription -Subscription $subscriptionId -tenant $TenantId -ErrorAction Stop
    }
    catch
    {
        write-output "Azure Powershell login required."
        break
    }
}

# save credentials
$contextfile=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext.txt"
Save-AzContext -Path $contextfile -Force




$Scriptrun=
@'

# The core concept of this script is:
#
#   In case of a Photon OS iso in parameter Uri, it cannot be attached to an Azure virtual machine.
#      The script configures the already added disk as Ventoy bootable disk containing the downloaded Photon OS iso bits, makes a vhd file with disk2vhd and does a blob upload vhd file for generating the Azure image.
#      The Ventoy tool luckily is available for x86_64 Windows + Linux and arm64 Windows + Linux. 
#      The disk2vhd tool is available for x86_64 Windows and arm64 Windows.
# 
#   In case of a Photon OS vhd file in parameter Uri, the Photon OS vhd file bits are downloaded and a blob upload vhd file for generating the Azure image is processed.
#

$PSDefaultParameterValues = @{ 'out-file:encoding' = 'ascii' }
$IsVhdUploaded=$env:public + [IO.Path]::DirectorySeparatorChar + "VhdUploaded.txt"
$tmpfilename=split-path -path $Uri -Leaf

if ($tmpfilename.ToLower().EndsWith('.iso'))
{
    $tmpname=($tmpfilename -split ".iso")[0] + ".iso"
    $vhdfile=$tmppath + [io.path]::DirectorySeparatorChar+($tmpfilename -split ".iso")[0] + ".vhd"
    $downloadfile=$vhdfile
}
else
{
    $tmpname=($tmpfilename -split ".vhd")[0] + ".vhd"
    $vhdfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpname
    $downloadfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpfilename
}



#
#   A) The script is started in localsystem account. In LocalSystem context there is no possibility to connect outside.
#      Hence, the script creates a run once scheduled task with user impersonation and executing the downloaded powershell script.
#      There are some hacks in localsystem context to make a run-once-scheduled task with user logon type.
#   B) Portion of the script uses Azure Powershell.
#

if ($env:username -ine $HelperVMLocalAdminUser)
{
    $filetostart=$MyInvocation.MyCommand.Source
    # $LocalUser=$env:computername + "\" + $HelperVMLocalAdminUser
    $LocalUser=$HelperVMLocalAdminUser

	$PowershellFilePath =  "$PsHome\powershell.exe"
    $Taskname = "PhotonProcessing"
	$Argument = "\"""+$PowershellFilePath +"\"" -WindowStyle Hidden -NoLogo -NoProfile -Executionpolicy unrestricted -command \"""+$filetostart+"\"""

    # Scheduled task run takes time.
    $timeout=3600

    $i=0
    $rc=0
    do
    {
        $i++
        try
        {
            if ($rc -eq 0)
            {
                schtasks.exe /create /F /TN "$Taskname" /tr $Argument /SC ONCE /ST 00:00 /RU ${LocalUser} /RP ${HelperVMLocalAdminPwd} /RL HIGHEST /NP
                start-sleep -s 1
                schtasks /Run /TN "$Taskname" /I
                start-sleep -s 1
                $rc=1
            }
            if ($rc -eq 1)
            {
                start-sleep -s 1
                $i++
            }
        }
        catch {}
    }
    until ((test-path(${IsVhdUploaded})) -or ($i -gt $timeout))
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
        if ($disk.FreeGB -gt 35)
        {

            install-module PS7Zip -force

            if ($tmpfilename.ToLower().EndsWith('.iso'))
            {

                # Partition disk and assign driveletter U
                $TmpFile="$env:TEMP\Drive.txt"
                write-output 'select disk 2'                          >"$TmpFile"
                write-output 'ATTRIBUTES DISK CLEAR READONLY'        >>"$TmpFile"
                write-output 'clean'                                 >>"$TmpFile"
                write-output 'create partition primary'              >>"$TmpFile"
                write-output 'select partition 1'                    >>"$TmpFile"
                write-output 'active'                                >>"$TmpFile"
                write-output 'format fs=ntfs unit=64K label=U quick' >>"$TmpFile"
                write-output 'assign letter=U'                       >>"$TmpFile"
                diskpart /S "$TmpFile"

                # Download and install Ventoy
                c:\windows\system32\curl.exe -J -L -O "https://github.com/ventoy/Ventoy/releases/download/v1.0.88/ventoy-1.0.88-windows.zip"
                Expand-7Zip -FullName ventoy-1.0.88-windows.zip -destinationpath "$env:TEMP" -ErrorAction SilentlyContinue
                cmd /c "" "$env:TEMP\ventoy-1.0.88\Ventoy2Disk.exe" VTOYCLI /I /Drive:U: /NOUSBCheck

                # Download disk2vhd
                c:\windows\system32\curl.exe -J -L -O "https://download.sysinternals.com/files/Disk2vhd.zip"
                Expand-7Zip -FullName Disk2vhd.zip -destinationpath "$env:TEMP" -ErrorAction SilentlyContinue

                # reassign drive letter U to Ventoy volume
                $VentoyPath=(get-volume | SELECT -PROPERTY DriveLetter,FileSystemLabel, DriveType, Path | where-object {($_.DriveType -ieq 'fixed') -and ($_.FileSystemLabel -ieq 'ventoy')}).Path
                $partition = get-partition | select -property AccessPaths,diskNumber,partitionnumber | where-object {($_.AccessPaths -ieq $VentoyPath)}
                Set-Partition -DiskNumber $partition.disknumber -PartitionNumber $partition.partitionnumber -NewDriveLetter U

                # Download iso to the appropriate disk
                set-location -Path U:
                c:\windows\system32\curl.exe -J -O -L $Uri

                # mount iso to extract grub.cfg and isolinux.cfg for serial configuration
                mkdir U:\ventoy
                $mountResult = Mount-DiskImage U:\$tmpname -PassThru
                $driveLetter = ($mountResult | Get-Volume).DriveLetter
                copy ${driveLetter}:\boot\grub2\grub.cfg U:\ventoy\grub.cfg
                copy ${driveLetter}:\isolinux\isolinux.cfg U:\ventoy\isolinux.cfg
                copy ${driveLetter}:\isolinux\menu.cfg U:\ventoy\menu.cfg
                Dismount-DiskImage -ImagePath U:\$tmpname

                write-output "$tmpname" >"U:\ventoy\ventoy.dat"

                # Ventoy injection files
                $FileName = "U:\ventoy\grub.cfg"
                $Pattern = "set default=0"  
                $FileOriginal = Get-Content $FileName
                [String[]] $FileModified = @() 
                Foreach ($Line in $FileOriginal)
                {   
                    $FileModified += $Line
                    if ( $Line.Trim() -eq $Pattern ) 
                    {
                        #Add Lines after the selected pattern 
                        $FileModified += "serial --unit=0 --speed=115200"
                    } 
                }
                Set-Content -Path $fileName -Value $FileModified -Force

                $FileName = "U:\ventoy\isolinux.cfg"
                $Pattern = "timeout 0"  
                $FileOriginal = Get-Content $FileName
                [String[]] $FileModified = @() 
                Foreach ($Line in $FileOriginal)
                {   
                    $FileModified += $Line
                    if ( $Line.Trim() -eq $Pattern ) 
                    {
                        #Add Lines after the selected pattern 
                        $FileModified += "serial 0 115200"
                    } 
                }
                Set-Content -Path $fileName -Value $FileModified -Force

                $FileName = "U:\ventoy\menu.cfg"
                $Pattern = "append initrd="  
                $FileOriginal = Get-Content $FileName
                [String[]] $FileModified = @() 
                Foreach ($Line in $FileOriginal)
                {   
                    if ( $Line.Trim() -ilike "*$Pattern*" ) 
                    {
                        $FileModified += [System.String]::Concat($Line," console=ttyS0,115200")
                    }
                    else
                    {
                        $FileModified += $Line
                    }
                }
                Set-Content -Path $fileName -Value $FileModified -Force            

                $TmpFile="U:\ventoy\ventoy.json"
		        $variable=[System.String]::Concat('            "iso": "/',$tmpname,'",')
                write-output '{'                                                                                >"$TmpFile"
                write-output '    "theme": {'                                                                  >>"$TmpFile"
                write-output '        "display_mode": "serial_console",'                                       >>"$TmpFile"
                write-output '        "serial_param": "--unit=0 --speed=115200 --word=8 --parity=no --stop=1"' >>"$TmpFile"
                write-output '    },'                                                                          >>"$TmpFile"
                write-output '    "theme_legacy": {'                                                           >>"$TmpFile"
                write-output '        "display_mode": "serial_console",'                                       >>"$TmpFile"
                write-output '        "serial_param": "--unit=0 --speed=115200 --word=8 --parity=no --stop=1"' >>"$TmpFile"
                write-output '    },'                                                                          >>"$TmpFile"
                write-output '    "theme_uefi": {'                                                             >>"$TmpFile"
                write-output '        "display_mode": "serial_console",'                                       >>"$TmpFile"
                write-output '        "serial_param": "--unit=0 --speed=115200 --word=8 --parity=no --stop=1"' >>"$TmpFile"
                write-output '    },'                                                                          >>"$TmpFile"
                write-output '    "conf_replace_legacy": ['                                                    >>"$TmpFile"
                write-output '        {'                                                                       >>"$TmpFile"
                write-output "$variable"                                                                       >>"$TmpFile"
                write-output '            "org": "/boot/grub2/boot.cfg",'                                      >>"$TmpFile"
                write-output '            "new": "/ventoy/boot.cfg"'                                           >>"$TmpFile"
                write-output '        },'                                                                      >>"$TmpFile"
                write-output '        {'                                                                       >>"$TmpFile"
                write-output "$variable"                                                                       >>"$TmpFile"
                write-output '            "org": "/isolinux/menu.cfg",'                                        >>"$TmpFile"
                write-output '            "new": "/ventoy/menu.cfg"'                                           >>"$TmpFile"
                write-output '        },'                                                                      >>"$TmpFile"
                write-output '        {'                                                                       >>"$TmpFile"
                write-output "$variable"                                                                       >>"$TmpFile"
                write-output '            "org": "/isolinux/isolinux.cfg",'                                    >>"$TmpFile"
                write-output '            "new": "/ventoy/isolinux.cfg"'                                       >>"$TmpFile"
                write-output '        }'                                                                       >>"$TmpFile"
                write-output '    ],'                                                                          >>"$TmpFile"
                write-output '    "conf_replace_uefi": ['                                                      >>"$TmpFile"
                write-output '        {'                                                                       >>"$TmpFile"
                write-output "$variable"                                                                       >>"$TmpFile"
                write-output '            "org": "/boot/grub2/boot.cfg",'                                      >>"$TmpFile"
                write-output '            "new": "/ventoy/boot.cfg"'                                           >>"$TmpFile"
                write-output '        },'                                                                      >>"$TmpFile"
                write-output '        {'                                                                       >>"$TmpFile"
                write-output "$variable"                                                                       >>"$TmpFile"
                write-output '            "org": "/isolinux/menu.cfg",'                                        >>"$TmpFile"
                write-output '            "new": "/ventoy/menu.cfg"'                                           >>"$TmpFile"
                write-output '        },'                                                                      >>"$TmpFile"
                write-output '        {'                                                                       >>"$TmpFile"
                write-output "$variable"                                                                       >>"$TmpFile"
                write-output '            "org": "/isolinux/isolinux.cfg",'                                    >>"$TmpFile"
                write-output '            "new": "/ventoy/isolinux.cfg"'                                       >>"$TmpFile"
                write-output '        }'                                                                       >>"$TmpFile"
                write-output '    ]'                                                                           >>"$TmpFile"
                write-output '}'                                                                               >>"$TmpFile"

                # assign drive letter V to vtoyefi volume to be selectable for disk2vhd
                $VToyEFIPath=(get-volume | SELECT -PROPERTY DriveLetter,FileSystemLabel, DriveType, Path | where-object {($_.DriveType -ieq 'fixed') -and ($_.FileSystemLabel -ieq 'vtoyefi')}).Path
                $partition = get-partition | select -property AccessPaths,diskNumber,partitionnumber | where-object {($_.AccessPaths -ieq $VToyEFIPath)}
                Set-Partition -DiskNumber $partition.disknumber -PartitionNumber $partition.partitionnumber -NewDriveLetter V

                # Make vhd file
                cmd /c "$env:TEMP\disk2vhd64.exe" /accepteula -c U: V: $vhdfile

            }
            else
            {
                if (!(Test-Path $vhdfile))
                {
                    # Invoke-WebRequest $Uri -OutFile $tmpfilename
                    c:\windows\system32\curl.exe -J -O -L $Uri
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
    }

    if (Test-Path $vhdfile)
    {
	    # Azure login
	    $azcontext=get-azcontext
	    if ($azcontext)
	    {
		    $result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
		    if ($result)
		    {
			    $storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
			    if ($storageaccount)
			    {
                    $result=get-azstoragecontainer -Name ${HelperVMContainerName} -Context $storageaccount.Context -ErrorAction SilentlyContinue
                    if ($result)
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
    }

}


'@

# create lab resource group if it does not exist
$result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
if ( -not $($result))
{
    New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName
}

# storageaccount
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if ( -not $($storageaccount))
{
	$storageaccount=New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind $StorageKind -SkuName $StorageAccountType -ErrorAction SilentlyContinue
	if ( -not $($storageaccount))
    {
        write-output "Storage account has not been created. Check if the name is already taken."
        break
    }
}
do {start-sleep -Milliseconds 1000} until ($((get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).ProvisioningState) -ieq "Succeeded")
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue


$result=get-azstoragecontainer -Name ${HelperVMContainerName} -Context $storageaccount.Context -ErrorAction SilentlyContinue
if ( -not $($result))
{
    new-azstoragecontainer -Name ${HelperVMContainerName} -Context $storageaccount.Context -ErrorAction SilentlyContinue -Permission Blob
}

$Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.Name -ieq $HelperVMDiskName)}
if (-not $($Disk))
{
	# a temporary virtual machine is necessary because inside it downloads Photon and uploads the extracted disk as image base.

	[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName -ErrorAction SilentlyContinue
	if (-not ($VM))
	{
    	# networksecurityruleconfig
    	$nsg=get-AzNetworkSecurityGroup -Name $HelperVMnsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    	if ( -not $($nsg))
    	{
    		$nsgRule1 = New-AzNetworkSecurityRuleConfig -Name nsgRule1 -Description "Allow SSH" `
    		-Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
    		-SourceAddressPrefix Internet -SourcePortRange * `
    		-DestinationAddressPrefix * -DestinationPortRange 22

    		$nsgRule2 = New-AzNetworkSecurityRuleConfig -Name nsgRule2 -Description "Allow RDP" `
    		-Access Allow -Protocol Tcp -Direction Inbound -Priority 120 `
    		-SourceAddressPrefix Internet -SourcePortRange * `
    		-DestinationAddressPrefix * -DestinationPortRange 3389
    		$nsg = New-AzNetworkSecurityGroup -Name $HelperVMnsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $nsgRule1,$nsgRule2
    	}

    	# set network if not already set
    	$vnet = get-azvirtualnetwork -name $HelperVMNetworkName -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
    	if ( -not $($vnet))
    	{
    		$ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet -AddressPrefix $HelperVMSubnetAddressPrefix -NetworkSecurityGroup $nsg
    		$vnet = New-AzVirtualNetwork -Name $HelperVMNetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $HelperVMVnetAddressPrefix -Subnet $ServerSubnet
    		$vnet | Set-AzVirtualNetwork
    	}

		# create the temporary virtual machine

		# virtual machine local admin setting
		$VMLocalAdminSecurePassword = ConvertTo-SecureString $HelperVMLocalAdminPwd -AsPlainText -Force
		$LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($HelperVMLocalAdminUser, $VMLocalAdminSecurePassword)

		# Create a public IP address
		$nic=get-AzNetworkInterface -Name $HelperVMNICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
		if ( -not $($nic))
		{
			$pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $HelperVMPublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
			# Create a virtual network card and associate with public IP address and NSG
			$nic = New-AzNetworkInterface -Name $HelperVMNICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
				-SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
		}

		# Create a virtual machine configuration
		$vmConfig = New-AzVMConfig -VMName $HelperVMName -VMSize $HelperVMsize | `
		Add-AzVMNetworkInterface -Id $nic.Id

        # Get-AzVMImage -Location switzerlandnorth -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2019-datacenter-with-containers-smalldisk-g2
        $productversion=((get-azvmimage -Location $LocationName -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku)[(get-azvmimage -Location $LocationName -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku).count -1 ]).version

		$vmimage= get-azvmimage -Location $LocationName -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku -Version $productversion
		if (-not ([Object]::ReferenceEquals($vmimage,$null)))
		{
			if (-not ([Object]::ReferenceEquals($vmimage.PurchasePlan,$null)))
			{
				$agreementTerms=Get-AzMarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
				Set-AzMarketplaceTerms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name -Terms $agreementTerms -Accept
				$agreementTerms=Get-AzMarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
				Set-AzMarketplaceTerms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name -Terms $agreementTerms -Accept
				$vmConfig = Set-AzVMPlan -VM $vmConfig -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
			}

			$vmConfig = Set-AzVMOperatingSystem -Windows -VM $vmConfig -ComputerName $HelperVMComputerName -Credential $LocalAdminUserCredential | `
			Set-AzVMSourceImage -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku -Version $productversion		
			$vmConfig | Set-AzVMBootDiagnostic -Disable

            $Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.Name -ieq $HelperVMDiskName)}
            if (-not $($Disk))
            {
                $diskConfig = New-AzDiskConfig -AccountType 'Standard_LRS' -Location $LocationName -HyperVGeneration $HyperVGeneration -CreateOption Empty -DiskSizeGB ${HelperVMDiskSizeGB} -OSType Linux
                $Disk = New-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $HelperVMDiskName -Disk $diskConfig
                do {start-sleep -Milliseconds 1000} until ($((get-azdisk -ResourceGroupName $ResourceGroupName -DiskName $HelperVMDiskName).ProvisioningState) -ieq "Succeeded")
                $vmConfig = Add-AzVMDataDisk -VM $vmConfig -ManagedDiskId $Disk.Id -Name $HelperVMDiskName -Lun 1 -CreateOption Attach
            }

			# Create the virtual machine		
			New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig
			
			$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName			
			Set-AzVMBootDiagnostic -VM $VM -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName			
		}
	}

    $objBlob=get-azstorageblob -Container $HelperVMContainerName -Blob $BlobName -Context $storageaccount.Context -ErrorAction SilentlyContinue
	$objVM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName -status -ErrorAction SilentlyContinue
	if ((-not ([Object]::ReferenceEquals($objVM,$null))) -and (!($objBlob)))
	{
		# Prepare scriptfile
		$contextfileEncoded=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext_enc.txt"
		if ((test-path($contextfileEncoded)) -eq $true) {remove-item -path ($contextfileEncoded) -force}
		certutil -encode $contextfile $contextfileEncoded
		$content = get-content -path $contextfileEncoded
		$ScriptFile = $($env:public) + [IO.Path]::DirectorySeparatorChar + "importazcontext.ps1"
		$value = '$CachedAzContext=@'+"'`r`n"
		# https://stackoverflow.com/questions/42407136/difference-between-redirection-to-null-and-out-null
		$null = new-item $ScriptFile -type file -force -value $value
		out-file -inputobject $content -FilePath $ScriptFile -Encoding ASCII -Append
		out-file -inputobject "'@" -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$Uri="'+$Uri+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$tmppath="'+$HelperVMsize_TempPath+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$tenant="'+$((get-azcontext).tenant.id)+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ResourceGroupName="'+$ResourceGroupName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$LocationName="'+$LocationName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$StorageAccountName="'+$StorageAccountName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ImageName="'+$ImageName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$HelperVMContainerName="'+$HelperVMContainerName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$HelperVMLocalAdminUser="'+$HelperVMLocalAdminUser+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$HelperVMLocalAdminPwd="'+$HelperVMLocalAdminPwd+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		out-file -inputobject $ScriptRun -FilePath $ScriptFile -Encoding ASCII -append
		remove-item -path ($contextfileEncoded) -force

        # Extensions preparation
		$Blobtmp="importazcontext.ps1"
        $Extensions = Get-AzVMExtensionImage -Location $LocationName -PublisherName "Microsoft.Compute" -Type "CustomScriptExtension"
        $ExtensionPublisher= $Extensions[$Extensions.count-1].PublisherName
        $ExtensionType = $Extensions[$Extensions.count-1].Type
        $ExtensionVersion = (($Extensions[$Extensions.count-1].Version)[0..2]) -join ""

		# blob upload of scriptfile
        $result=get-azstorageblob -Container $HelperVMContainerName -Blob ${BlobTmp} -Context $storageaccount.Context -ErrorAction SilentlyContinue
        if (!($result))
		{
            Set-AzStorageBlobContent -Container ${HelperVMContainerName} -File $ScriptFile -Blob ${BlobTmp} -BlobType Block -Context $storageaccount.Context
		}

        # Remote install Az module
        $commandToExecute="powershell.exe Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force ; powershell install-module -name Az -force -ErrorAction SilentlyContinue; shutdown.exe /r /t 0"
        $ScriptSettings = @{}
        $ProtectedSettings = @{"storageAccountName" = $StorageAccountName; "storageaccountkey" = ($storageaccountkey[0]).value ; "commandToExecute" = $commandToExecute }
        Set-AzVMExtension -ResourceGroupName $ResourceGroupName -Location $LocationName -VMName $HelperVMName -Name $ExtensionType -Publisher $ExtensionPublisher -ExtensionType $ExtensionType -TypeHandlerVersion $ExtensionVersion -Settings $ScriptSettings -ProtectedSettings $ProtectedSettings
     	Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $HelperVMName -Name $ExtensionType -force -ErrorAction SilentlyContinue
        # wait for the reboot
        start-sleep 15

        # Run scriptfile
        $Run = "C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension\1.10.14\Downloads\0\$BlobTmp"
        Set-AzVMCustomScriptExtension -Name "CustomScriptExtension" -Location $LocationName -ResourceGroupName $ResourceGroupName -VMName $HelperVMName -StorageAccountName $StorageAccountName -ContainerName $HelperVMContainerName -FileName $BlobTmp -Run $Run
	}
}

if ((test-path($contextfile))) { remove-item -path ($contextfile) -force -ErrorAction SilentlyContinue }

$Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.Name -ieq $HelperVMDiskName)}
if (-not $($Disk))
{
    $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${HelperVMContainerName}/${ImageName}"
    $storageAccountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
    $diskConfig = New-AzDiskConfig -AccountType $StorageAccountType -Location $LocationName -HyperVGeneration $HyperVGeneration -CreateOption Import -StorageAccountId $storageAccountId -SourceUri $urlOfUploadedVhd
    New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $HelperVMDiskName -ErrorAction SilentlyContinue
}

$Image=get-AzImage | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.name -ieq $Imagename)}
if (-not $($Image))
{
    $Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.Name -ieq $HelperVMDiskName)}
    if (-not ([Object]::ReferenceEquals($Disk,$null)))
    {
        $imageconfig=new-azimageconfig -location $LocationName -HyperVGeneration $HyperVGeneration
        $imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsState Generalized -OsType Linux -ManagedDiskId $Disk.ID
        new-azimage -ImageName $ImageName -ResourceGroupName $ResourceGroupName -image $imageconfig -ErrorAction SilentlyContinue
    }
}

# Delete virtual machine with its objects
$AzImage=get-AzImage | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.name -ieq $Imagename)}
if ([Object]::ReferenceEquals($AzImage,$null))
{
    write-Output "Error: Image creation failed."
}


$obj=Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
    $HelperVMDiskName=$obj.StorageProfile.OsDisk.Name
    Remove-AzVM -ResourceGroupName $resourceGroupName -Name $HelperVMName -force -ErrorAction SilentlyContinue
    $obj=Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $HelperVMDiskName -ErrorAction SilentlyContinue
    if (-not ([Object]::ReferenceEquals($obj,$null)))
    {
        Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $HelperVMDiskName -Force -ErrorAction SilentlyContinue
    }
}



$obj=Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $HelperVMNICName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzNetworkInterface -Name $HelperVMNICName -ResourceGroupName $ResourceGroupName -force -ErrorAction SilentlyContinue
}

$obj=Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $HelperVMPublicIPDNSName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $HelperVMPublicIPDNSName -Force -ErrorAction SilentlyContinue
}

$obj=Get-AzVirtualNetwork -Name $HelperVMNetworkName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzVirtualNetwork -Name $HelperVMNetworkName -ResourceGroupName $ResourceGroupName -Force -ErrorAction SilentlyContinue
}

$obj=Get-AzNetworkSecurityGroup -Name $HelperVMnsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzNetworkSecurityGroup -Name $HelperVMnsgName -ResourceGroupName $ResourceGroupName -Force -ErrorAction SilentlyContinue
}

$obj=Get-AzStorageContainer -Name ${HelperVMContainerName} -Context $storageaccount.Context  -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzStorageContainer -Name ${HelperVMContainerName} -Context $storageaccount.Context -Force -ErrorAction SilentlyContinue
}

$obj=Get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force -ErrorAction SilentlyContinue
}
