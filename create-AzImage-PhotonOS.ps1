# .SYNOPSIS
#  The Azure Virtual Machine Image builder script creates an Azure image of VMware Photon OS.
#
# .DESCRIPTION
#  Actually there are no official Azure marketplace images of VMware Photon OS. You can create one using the official .vhd file of a specific VMware Photon OS build.
#
#  VMware Photon OS build download links:
#    Photon OS 4.0 GA Azure VHD:                         https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz
#      Photon OS 4.0 RC Azure VHD:                       https://packages.vmware.com/photon/4.0/RC/azure/photon-azure-4.0-a3a49f540.vhd.tar.gz
#      Photon OS 4.0 Beta Azure VHD:                     https://packages.vmware.com/photon/4.0/Beta/azure/photon-azure-4.0-d98e681.vhd.tar.gz
#    Photon OS 3.0 Revision 2 Azure VHD:                 https://packages.vmware.com/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz
#    Photon OS 3.0 GA Azure VHD:                         https://packages.vmware.com/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz
#       Photon OS 3.0 RC Azure VHD:                      https://packages.vmware.com/photon/3.0/RC/azure/photon-azure-3.0-49fd219.vhd.tar.gz
#       Photon OS 3.0 Beta:                              https://packages.vmware.com/photon/3.0/Beta/azure/photon-azure-3.0-5e45dc9.vhd.tar.gz
#    Photon OS 2.0 GA Azure VHD gz file:                 https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-304b817.vhd.gz
#    Photon OS 2.0 GA Azure VHD cloud-init provisioning: https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-3146fa6.tar.gz
#       Photon OS 2.0 RC Azure VHD - gz file:            https://packages.vmware.com/photon/2.0/RC/azure/photon-azure-2.0-31bb961.vhd.gz
#       Photon OS 2.0 Beta Azure VHD:                    https://packages.vmware.com/photon/2.0/Beta/azure/photon-azure-2.0-8553d58.vhd
#
#  To simplify the process this Azure Virtual Machine Image builder script does a device login on Azure, and uses the specified location and resource group to create an Azure image.
#  Actually, without specifying the VMware Photon OS build, it creates an Photon OS 4.0 GA Azure image.
#
#  
#  This Azure Virtual Machine Image builder script uses Microsoft Azure Powershell and Microsoft Azure CLI as well. It installs those components if necessary.
#  It doesn't make use of the Azure Image Builder template creation method.
#
#  With the start it does twice trigger an Azure login using the device code method.
#  
#      az : WARNING: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxxx to authenticate.
#      In Zeile:1 Zeichen:13
#      + $azclilogin=az login --use-device-code
#          +             ~~~~~~~~~~~~~~~~~~~~~~~~~~
#          + CategoryInfo          : NotSpecified: (WARNING: To sig...o authenticate.:String) [], RemoteException
#          + FullyQualifiedErrorId : NativeCommandError
#
#    WARNUNG: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxxx to authenticate.
#
#  The Azure CLI and Azure Powershell output shows up as warning (see above).
#  You will have to open a webbrowser, and fill in the code given by the Azure Powershell login output and by the Azure CLI login output.
#
#  The script first creates a temporary Azure windows virtual machine to not require to temporarily download the Photon OS bits locally.
#  Inside the windows virtual machine customization process, the Photon release Azure .vhd file is downloaded. You can specify the Photon release download link as param value of $DownloadURL.
#  The extracted VMware Photon OS release .vhd file is uploaded as Azure page blob, and after the Azure Photon image has been created, the temporary Windows virtual machine is deleted.
#  The temporary virtual machine operating system is Microsoft Windows Server 2019 on a specifiable Hyper-V generation virtual hardware V1/v2 using the Azure offering Standard_E4s_v3.
#  Azure virtual hardware generation related weblink
#    - https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2
#
#  It would be nice to avoid some cmdlets-specific warning output on the host screen during run. You can safely ignore Warnings, especially:
#  "WARNUNG: System.ArgumentException: Argument passed in is not serializable." + appendings like "Microsoft.WindowsAzure.Commands.Common.MetricHelper"
#  "az storage blob upload --account-name" + appendings like "CategoryInfo          : NotSpecified: (:String) [], RemoteException"
#  "No Run File has been assigned, and the Custom Script extension will try to use the first specified File Name as the Run File."
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
#
# .PARAMETER azconnect
#   Azure powershell devicecode login
# .PARAMETER azclilogin
#   Azure CLI devicecode login
# .PARAMETER DownloadURL
#   Specifies the URL of the VMware Photon OS .vhd.tar.gz file
# .PARAMETER Location
#   Azure location name where to create or lookup the resource group
# .PARAMETER ResourceGroupName
#   Azure resourcegroup name
# .PARAMETER StorageAccountName
#   Azure storage account name
# .PARAMETER StorageAccountType
#   Storage AccountType
# .PARAMETER ContainerName
#   Azure storage container name
# .PARAMETER Imagename
#   Azure image name for the uploaded VMware Photon OS
# .PARAMETER HyperVGeneration
#   Hyper-V Generation (V1, V2)
# .PARAMETER DiskName
#   Name of the DiskName in the Image
#
# .EXAMPLE
#    ./create-AzImage-PhotonOS.ps1 -DownloadURL "https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-304b817.vhd.gz" -ResourceGroupName photonoslab -Location switzerlandnorth
#

[CmdletBinding()]
param(
[Parameter(Mandatory = $false)]
[ValidateNotNull()]
[string]$azconnect,
[Parameter(Mandatory = $false)]
[ValidateNotNull()]
[string]$azclilogin,

[Parameter(Mandatory = $true)]
[ValidateSet('https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz', `
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
[String]$DownloadURL="https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz",


[Parameter(Mandatory = $true)][ValidateNotNull()]
[ValidateSet('eastasia','southeastasia','centralus','eastus','eastus2','westus','northcentralus','southcentralus',`
'northeurope','westeurope','japanwest','japaneast','brazilsouth','australiaeast','australiasoutheast',`
'southindia','centralindia','westindia','canadacentral','canadaeast','uksouth','ukwest','westcentralus','westus2',`'koreacentral','koreasouth','francecentral','francesouth','australiacentral','australiacentral2',`
'uaecentral','uaenorth','southafricanorth','southafricawest','switzerlandnorth','switzerlandwest',`
'germanynorth','germanywestcentral','norwaywest','norwayeast','brazilsoutheast','westus3')]
[string]$Location,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupName,

[Parameter(Mandatory = $false)][ValidateNotNull()][ValidateLength(3,24)][ValidatePattern("[a-z0-9]")]
[string]$StorageAccountName=$ResourceGroupName.ToLower()+"storage",

[Parameter(Mandatory = $false)]
[string]$StorageAccountType="Standard_LRS",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ContainerName = "disks",

[Parameter(Mandatory = $true)]
[ValidateSet('V1','V2')]
[string]$HyperVGeneration="V2",

[Parameter(Mandatory = $false)]
[string]$ImageName=$(((split-path -path $([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($DownloadURL)) -Leaf) -split ".vhd")[0] + "_" + $HyperVGeneration + ".vhd"),

[Parameter(Mandatory = $false)]
[string]$DiskName="PhotonOS"
)


# https://github.com/Azure/azure-powershell/blob/master/documentation/breaking-changes/breaking-changes-messages-help.md
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

# Check Windows Powershell environment. Original codesnippet parts from https://www.powershellgallery.com/packages/Az.Accounts/2.2.5/Content/Az.Accounts.psm1
$PSDefaultParameterValues.Clear()
Set-StrictMode -Version Latest

function Test-DotNet
{
    try
    {
        if ((Get-PSDrive 'HKLM' -ErrorAction Ignore) -and (-not (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -ErrorAction Stop | Get-ItemPropertyValue -ErrorAction Stop -Name Release | Where-Object { $_ -ge 461808 })))
        {
            throw ".NET Framework versions lower than 4.7.2 are not supported in Az. Please upgrade to .NET Framework 4.7.2 or higher."
            exit
        }
    }
    catch [System.Management.Automation.DriveNotFoundException]
    {
        Write-Verbose ".NET Framework version check failed."
        exit
    }
}

if ($true -and ($PSEdition -eq 'Desktop'))
{
    if ($PSVersionTable.PSVersion -lt [Version]'5.1')
    {
        throw "PowerShell versions lower than 5.1 are not supported in Az. Please upgrade to PowerShell 5.1 or higher."
        exit
    }
    Test-DotNet
}

if ($true -and ($PSEdition -eq 'Core'))
{
    if ($PSVersionTable.PSVersion -lt [Version]'6.2.4')
    {
        throw "Current Az version doesn't support PowerShell Core versions lower than 6.2.4. Please upgrade to PowerShell Core 6.2.4 or higher."
        exit
    }
}

# check Azure CLI user install
if (test-path("$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin"))
{
    $Remove = "$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin"
    $env:Path = ($env:Path.Split(';') | Where-Object -FilterScript {$_ -ne $Remove}) -join ';'
    $env:path="$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path
}

$version=""
try
{
    $version=az --version 2>$null
    $version=(($version | select-string "azure-cli")[0].ToString().Replace(" ","")).Replace("azure-cli","")
}
catch {}

# Update was introduced in 2.11.0, see https://docs.microsoft.com/en-us/cli/azure/update-azure-cli
if (($version -eq "") -or ($version -lt "2.11.0"))
{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList "/a AzureCLI.msi /qb TARGETDIR=$env:APPDATA\azure-cli /quiet"
    if (!(test-path("$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin")))
    {
        throw "Azure CLI installation failed."
        exit
    }
    else
    {
        $Remove = "$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin"
        $env:Path = ($env:Path.Split(';') | Where-Object -FilterScript {$_ -ne $Remove}) -join ';'
        $env:path="$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path

        $version=az --version 2>$null
        $version=(($version | select-string "azure-cli")[0].ToString().Replace(" ","")).Replace("azure-cli","")
    }
    if (test-path(.\AzureCLI.msi)) {rm .\AzureCLI.msi}
}
if ($version -lt "2.19.1")
{
    az upgrade --yes --all 2>&1 | out-null
}


# check Azure Powershell
# https://github.com/Azure/azure-powershell/issues/13530
# https://github.com/Azure/azure-powershell/issues/13337
if (!(([string]::IsNullOrEmpty((get-module -name Az.Accounts -listavailable)))))
{
    if ((get-module -name Az.Accounts -listavailable).Version.ToString() -lt "2.2.5") 
    {
        update-module Az -Scope User -RequiredVersion 5.5 -MaximumVersion 5.5 -force -ErrorAction SilentlyContinue
    }
}
else
{
    install-module Az -Scope User -RequiredVersion 5.5 -MaximumVersion 5.5 -force -ErrorAction SilentlyContinue
}


# Uri
$Uri=$([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($DownloadURL))
# settings of the temporary virtual machine
# -----------------------------------------
$VMSize="Standard_E4s_v3" # This default virtual machine size offering includes a d: drive with 60GB non-persistent capacity
$VMSize_TempPath="d:" # $DownloadURL file is downloaded and extracted on this drive. Depending of the VMSize offer, it includes built-in an additional non persistent  drive.
# network setting
$NetworkName = "w2k19network"
# virtual network and subnets setting
$SubnetAddressPrefix = "192.168.1.0/24"
$VnetAddressPrefix = "192.168.0.0/16"
# virtual machine setting
$ComputerName = "w2k19"
$VMName = $ComputerName
$NICName = $ComputerName + "nic"
$VMLocalAdminUser = "LocalAdminUser"
$VMLocalAdminPwd="Secure2020123!" #12-123 chars
$PublicIPDNSName="mypublicdns$(Get-Random)"
$nsgName = "myNetworkSecurityGroup"
$publisherName = "MicrosoftWindowsServer"
$offerName = "WindowsServer"
$skuName = "2019-datacenter-with-containers-smalldisk-g2"
$marketplacetermsname= $skuName
# Get-AzVMImage -Location switzerlandnorth -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2019-datacenter-with-containers-smalldisk-g2

if (!(Get-variable -name azclilogin -ErrorAction SilentlyContinue))
{
    $azclilogin=az login --use-device-code
}

if (!(Get-variable -name azclilogin -ErrorAction SilentlyContinue))
{
    write-host "Azure CLI login required."
    exit
}

if (!(Get-variable -name azconnect -ErrorAction SilentlyContinue))
{
    $azconnect=connect-azaccount -devicecode
	$AzContext=$null
}

if (!(Get-variable -name azconnect -ErrorAction SilentlyContinue))
{
    write-host "Azure Powershell login required."
    exit
}

if (!(Get-variable -name AzContext -ErrorAction SilentlyContinue))
{
	$AzContext = Get-AzContext
    $ArmToken = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
    $AzContext.'Account',
    $AzContext.'Environment',
    $AzContext.'Tenant'.'Id',
    $null,
    [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never,
    $null,
    'https://management.azure.com/'
    )
    $tenantId = ($AzContext).Tenant.Id
    $accessToken = (Get-AzAccessToken -ResourceUrl "https://management.core.windows.net/" -TenantId $tenantId).Token
}
else
{
    write-host "Azure Powershell connect required."
    exit
}


# save credentials
$contextfile=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext.txt"
Save-AzContext -Path $contextfile -Force

#Set the context to the subscription Id where Managed Disk exists and where virtual machine will be created if necessary
$subscriptionId=(get-azcontext).Subscription.Id
# set subscription
az account set --subscription $subscriptionId

$Scriptrun=
@'

$RootDrive=(get-item $tmppath).Root.Name
$tmpfilename=split-path -path $Uri -Leaf
$tmpname=($tmpfilename -split ".vhd")[0] + ".vhd"
$vhdfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpname
$downloadfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpfilename
$IsVhdUploaded=$env:public + "\VhdUploaded.txt"

# In LocalSystem context there is no possibility to connect outside. Hence, the following snippet runs a schedule task once with impersonation to user VMLocalAdminUser.
if ($env:username -ine $VMLocalAdminUser)
{
    $filetostart=$MyInvocation.MyCommand.Source
    $LocalUser=$env:computername + "\" + $VMLocalAdminUser

    $Identifier="123"
	$PowershellFilePath =  "$PsHome\powershell.exe"
    $Taskname = "ScheduledPhotonProcessing" + $Identifier
	$Argument = "\"""+$PowershellFilePath +"\"" -WindowStyle Hidden -NoLogo -NoProfile -Executionpolicy unrestricted -command \"""+$filetostart+"\"""

    $begintime = "00:0" + (get-random -count 1 -inputobject (0..9))[0]
    # https://stackoverflow.com/questions/6939548/a-workaround-for-the-fact-that-a-scheduled-task-in-windows-requires-a-user-to-be/6982193

    # Scheduled tasks run takes time. Set timeout value to 1 hour.
    $timeout=3600

    $i=0
    $rc=$null
    do
    {
        start-sleep -m 1000
        $i++
        $rc=schtasks.exe /create /f /tn "$Taskname" /tr $Argument /SC ONCE /SD "01/01/2018" /ST $begintime /RU ${LocalUser} /RP ${VMLocalAdminPwd} /RL HIGHEST
    }
    until (($rc -ne $null) -or ($i -gt $timeout))
    if ($rc -eq $null) {exit}

    $tmpxmlfile=$tmppath+"\xml"+ $Identifier+".xml"
    $rcInner=$null
    try
    {
        schtasks /query /XML /tn "$Taskname" >"$tmpxmlfile"
        schtasks /delete /TN "$Taskname" /F
        (get-content ("$tmpxmlfile")).replace('<LogonType>InteractiveToken</LogonType>','<LogonType>Password</LogonType>') |set-content "$tmpxmlfile"
        (get-content ("$tmpxmlfile")).replace('<ExecutionTimeLimit>PT72H</ExecutionTimeLimit>','<ExecutionTimeLimit>PT1H</ExecutionTimeLimit>') |set-content "$tmpxmlfile"

        $rcInner=schtasks.exe /create /f /tn "$Taskname" /RU ${LocalUser} /RP ${VMLocalAdminPwd} /XML "$tmpxmlfile"
        # if (test-path(${tmpxmlfile})) {remove-item -Path ${tmpxmlfile}}
    }
    catch{}
    if ($rcInner -ne $null)
    {
        start-sleep -s 1
        schtasks /Run /TN "$Taskname" /I	
        $i=0
        do
        {
            start-sleep -m 1000
            $i++
        }
        until ((test-path(${IsVhdUploaded})) -or ($i -gt $timeout))

        schtasks /End /TN "$Taskname"
        start-sleep -s 1
        schtasks /delete /TN "$Taskname" /F
    }
    exit
}

# check Azure CLI user install
if (test-path("$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin"))
{
    $Remove = "$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin"
    $env:Path = ($env:Path.Split(';') | Where-Object -FilterScript {$_ -ne $Remove}) -join ';'
    $env:path="$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path
}

$version=""
try
{
    $version=az --version 2>$null
    $version=(($version | select-string "azure-cli")[0].ToString().Replace(" ","")).Replace("azure-cli","")
}
catch {}

# Update was introduced in 2.11.0, see https://docs.microsoft.com/en-us/cli/azure/update-azure-cli
if (($version -eq "") -or ($version -lt "2.11.0"))
{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList "/a AzureCLI.msi /qb TARGETDIR=$env:APPDATA\azure-cli /quiet"
    if (!(test-path("$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin")))
    {
        throw "Azure CLI installation failed."
        exit
    }
    else
    {
        $Remove = "$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin"
        $env:Path = ($env:Path.Split(';') | Where-Object -FilterScript {$_ -ne $Remove}) -join ';'
        $env:path="$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path

        $version=az --version 2>$null
        $version=(($version | select-string "azure-cli")[0].ToString().Replace(" ","")).Replace("azure-cli","")
    }
    if (test-path(.\AzureCLI.msi)) {rm .\AzureCLI.msi}
}
if ($version -lt "2.19.1")
{
    az upgrade --yes --all 2>&1 | out-null
}


# check Azure Powershell
# https://github.com/Azure/azure-powershell/issues/13530
# https://github.com/Azure/azure-powershell/issues/13337
if (!(([string]::IsNullOrEmpty((get-module -name Az.Accounts -listavailable)))))
{
    if ((get-module -name Az.Accounts -listavailable).Version.ToString() -lt "2.2.5") 
    {
        update-module Az -Scope User -RequiredVersion 5.5 -MaximumVersion 5.5 -force -ErrorAction SilentlyContinue
    }
}
else
{
    install-module Az -Scope User -RequiredVersion 5.5 -MaximumVersion 5.5 -force -ErrorAction SilentlyContinue
}


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
            if (!(Test-Path $vhdfile))
            {
                # Invoke-WebRequest $Uri -OutFile $tmpfilename
                c:\windows\system32\curl.exe -J -O -L $Uri
            }
            if ((Test-Path $downloadfile) -and ((([IO.Path]::GetExtension($tmpfilename)) -ieq ".gz")))
            {
                try
                {
                    c:\windows\system32\tar.exe -xzvf $downloadfile
                }
                catch{}
                if (!(Test-Path $vhdfile))
                {
                        # Windows tar does not extract photon-azure-2.0-304b817.vhd.gz but PS7Zip does.
                        install-module PS7Zip -force
                        # work directory must be path of $tmpfilename
                        Expand-7Zip -FullName $tmpfilename -destinationpath $tmpname
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
		$result = get-azresourcegroup -name $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue
		if ($result)
		{
			$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
			if ($storageaccount)
			{
				$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)
				$result=az storage container exists --account-name $StorageAccountName --account-key $storageaccountkey.value[0] --name $ContainerName | convertfrom-json
				if ($result.exists -eq $true)
				{
					$BlobName= $tmpname
					$result=az storage blob exists --account-key $storageaccountkey.value[0] --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobName} | convertfrom-json
					if ($result.exists -eq $false)
					{
						try {
						    az storage blob upload --account-name $StorageAccountName `
						    --account-key ($storageaccountkey[0]).value `
						    --container-name ${ContainerName} `
						    --type page `
						    --file $vhdfile `
						    --name ${BlobName}
                            $vhdfile | out-file -filepath $IsVhdUploaded -append
						} catch{}
					}			
				}
			}
		}
	}
}
shutdown.exe /r /t 0
'@

# create lab resource group if it does not exist
$result = get-azresourcegroup -name $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue
if ( -not $($result))
{
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location
}

# storageaccount
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if ( -not $($storageaccount))
{
	$storageaccount=New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $Location -Kind Storage -SkuName Standard_LRS -ErrorAction SilentlyContinue
	if ( -not $($storageaccount))
    {
        write-host "Storage account has not been created. Check if the name is already taken."
        break
    }
}
do {sleep -Milliseconds 1000} until ($((get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).ProvisioningState) -ieq "Succeeded") 
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)

$result=az storage container exists --account-name $storageaccountname --name ${ContainerName} --auth-mode login | convertfrom-json
if ($result.exists -eq $false)
{
	az storage container create --name ${ContainerName} --public-access blob --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
}

$BlobName=((split-path -path $Uri -Leaf) -split ".vhd")[0] + ".vhd"

$Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.Name -ieq $DiskName)}
if (-not $($Disk))
{
	# a temporary virtual machine is necessary because inside it downloads Photon and uploads the extracted disk as image base.

	[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
	if (-not ($VM))
	{
    	# networksecurityruleconfig
    	$nsg=get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    	if ( -not $($nsg))
    	{
    		$rdpRule1 = New-AzNetworkSecurityRuleConfig -Name myRdpRule -Description "Allow RDP" `
    		-Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
    		-SourceAddressPrefix Internet -SourcePortRange * `
    		-DestinationAddressPrefix * -DestinationPortRange 3389
    		$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $Location -SecurityRules $rdpRule1
    	}

    	# set network if not already set
    	$vnet = get-azvirtualnetwork -name $networkname -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
    	if ( -not $($vnet))
    	{
    		$ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet  -AddressPrefix $SubnetAddressPrefix -NetworkSecurityGroup $nsg
    		$vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $VnetAddressPrefix -Subnet $ServerSubnet
    		$vnet | Set-AzVirtualNetwork
    	}

		# create virtual machine
		# -----------

		# virtual machine local admin setting
		$VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPwd -AsPlainText -Force
		$LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

		# Create a public IP address
		$nic=get-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
		if ( -not $($nic))
		{
			$pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
			# Create a virtual network card and associate with public IP address and NSG
			$nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $Location `
				-SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
		}

		# Create a virtual machine configuration
		$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize | `
		Add-AzVMNetworkInterface -Id $nic.Id

        $productversion=((get-azvmimage -Location $Location -PublisherName $publisherName -Offer $offerName -Skus $skuName)[(get-azvmimage -Location $Location -PublisherName $publisherName -Offer $offerName -Skus $skuName).count -1 ]).version

		$vmimage= get-azvmimage -Location $Location -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $productversion
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

			$vmConfig = Set-AzVMOperatingSystem -Windows -VM $vmConfig -ComputerName $ComputerName -Credential $LocalAdminUserCredential | `
			Set-AzVMSourceImage -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $productversion

			# Create the virtual machine
			$VirtualMachine = New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig
		}
	}

    $objBlob=get-azstorageblob -Container $ContainerName -Blob $BlobName -Context $storageaccount.Context -ErrorAction SilentlyContinue
	$objVM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -status -ErrorAction SilentlyContinue
	if ((-not ([Object]::ReferenceEquals($objVM,$null))) -and (!($objBlob)))
	{
		# First remote install Az Module
		az vm extension set --publisher Microsoft.Compute --version 1.8 --name "CustomScriptExtension" --vm-name $vmName --resource-group $ResourceGroupName --settings "{'commandToExecute':'powershell.exe Install-module Az -force -ErrorAction SilentlyContinue;'}"
		Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name "CustomScriptExtension" -force
		
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
		$tmp='$tmppath="'+$VMSize_TempPath+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append	
		$tmp='$tenant="'+$((get-azcontext).tenant.id)+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ResourceGroupName="'+$ResourceGroupName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$Location="'+$Location+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$StorageAccountName="'+$StorageAccountName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ContainerName="'+$ContainerName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$VMLocalAdminUser="'+$VMLocalAdminUser+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$VMLocalAdminPwd="'+$VMLocalAdminPwd+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "AutoAdminLogon" -Value "1" -type String'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "DefaultUsername" -Value "$VMLocalAdminUser" -type String'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
        $tmp='Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "DefaultPassword" -Value "$VMLocalAdminPwd" -type String'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append

		out-file -inputobject $ScriptRun -FilePath $ScriptFile -Encoding ASCII -append

		remove-item -path ($contextfileEncoded) -force

		# Remote import azcontext and process blob upload from scriptfile
		$Blobtmp="importazcontext.ps1"
		$result=az storage blob exists --account-key ($storageaccountkey[0]).value --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobTmp} | convertfrom-json
		if ($result.exists -eq $false)
		{
			az storage blob upload --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value --container-name ${ContainerName} --type block --file $ScriptFile --name ${BlobTmp}
		}        
		$return=Set-AzVMCustomScriptExtension -ResourceGroupName $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue `
				-VMName $vmName `
				-Name "CustomScriptExtension" `
				-containername $ContainerName -storageaccountname $StorageAccountName `
				-Filename ${BlobTmp}	
		Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name "CustomScriptExtension" -force -ErrorAction SilentlyContinue

	}
}

if ((test-path($contextfile))) { remove-item -path ($contextfile) -force -ErrorAction SilentlyContinue }

$Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.Name -ieq $DiskName)}
if (-not $($Disk))
{
    $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
    $storageAccountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
    $diskConfig = New-AzDiskConfig -AccountType $StorageAccountType -Location $Location -HyperVGeneration $HyperVGeneration -CreateOption Import -StorageAccountId $storageAccountId -SourceUri $urlOfUploadedVhd
    New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $DiskName -ErrorAction SilentlyContinue
}

$Image=get-AzImage | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.name -ieq $Imagename)}
if (-not $($Image))
{
    $Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.Name -ieq $DiskName)}
    if (-not ([Object]::ReferenceEquals($Disk,$null)))
    {	
        $imageconfig=new-azimageconfig -location $Location -HyperVGeneration $HyperVGeneration
        $imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsState Generalized -OsType Linux -ManagedDiskId $Disk.ID
        new-azimage -ImageName $ImageName -ResourceGroupName $ResourceGroupName -image $imageconfig -ErrorAction SilentlyContinue
    }
}

# Delete virtual machine with its objects
$Image=get-AzImage | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.name -ieq $Imagename)}
if (-not ([Object]::ReferenceEquals($Image,$null)))
{
    $VirtualMachine=Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName
    if (-not ([Object]::ReferenceEquals($VirtualMachine,$null)))
       {
        $OsDiskName=$VirtualMachine.StorageProfile.OsDisk.Name
	    Remove-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -force -ErrorAction SilentlyContinue
	    Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $OsDiskName -Force -ErrorAction SilentlyContinue
    }
	Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $DiskName -Force -ErrorAction SilentlyContinue
    Remove-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -force -ErrorAction SilentlyContinue
    Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $PublicIPDNSName -Force -ErrorAction SilentlyContinue
    Remove-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -force -ErrorAction SilentlyContinue
    Remove-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -force -ErrorAction SilentlyContinue
    az storage container delete --name ${ContainerName} --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
    remove-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force -ErrorAction SilentlyContinue
}
else { write-host "Error: Image creation failed." }
