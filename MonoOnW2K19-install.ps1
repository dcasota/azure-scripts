

$folder = "c:\temp"
$log = "c:\temp\MonoLog.txt"

if (!(Test-Path $log)) {
    New-Item -Path $folder -ItemType Directory
    New-Item -Path $log -ItemType File
}
curl -Uri https://download.mono-project.com/archive/6.4.0/windows-installer/mono-6.4.0.198-x64-0.msi -Outfile "$folder\mono-6.4.0.198-x64-0.msi"
msiexec /i "$folder\mono-6.4.0.198-x64-0.msi" /quiet /qn /norestart /log $log

cd "$env:programfiles\mono-6.4.0.198-x64-0"
configure --prefix="$env:programfiles\mono-6.4.0.198-x64-0"
make
make install
cd $folder
curl -Uri https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -Outfile "$folder\nuget.exe"
