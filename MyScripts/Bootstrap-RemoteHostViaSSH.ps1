# Get a Windows 11 ISO ready to install
# Create new bootable Windows 11 ISO via D:\ drive with all of the files generated by Rufus
New-VHD -Path "E:\HDDs\Win11InstallerViaRufus\Win11_22H2_v2.vhdx" -Fixed -SizeBytes 10GB
# Use the Disk Management GUI to initialize the new disk and create a new simple NTFS volume and mount it as D:\ (or whatever letter)
# Use the Rufus GUI to create a bootable Windows 11 D:\ drive with all desired customizations
# Copy the boot files to a folder on a different letter drive like C:\
$ISOFilesDir = "C:\Win1122H2v2_ISO_via_Rufus"
$ISOFileOutputPath = "C:\Users\adminuser\Downloads\Custom_Win11_22H2_v2_adminuser_via_Rufus.iso"
if (!(Test-Path $ISOFilesDir)) {$null = New-Item -Path $ISOFilesDir -ItemType Directory -Force}
Copy-Item -Path D:\* -Destination $ISOFilesDir -Recurse -Force
# Make sure you have Windows ADK installed and run the following commands in an elevated PowerShell prompt
cd "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
Invoke-Expression ".\oscdimg.exe -m -o -u2 -udfver102 -bootdata:2#p0,e,b$ISOFilesDir\boot\etfsboot.com#pEF,e,b$ISOFilesDir\efi\microsoft\boot\efisys.bin -lWinBoot $ISOFilesDir $ISOFileOutputPath"

# Bootstrap new Windows Workstation
# You Just need to have SSHD installed and running on the remote host and default shell must be powershell.exe
# To get SSHD installed, on the new Windows 11 machine, lauch Powershell as admin and run the following command:
# Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/pldmgg/misc-powershell/master/MyScripts/Install-SSHD.ps1'))
# NOTE: This sets the default SSH shell to powershell.exe

# Next, from your local workstation, run:
$ScriptsDir = "C:\Scripts"
@("$ScriptsDir\temp", "$ScriptsDir\logs", "$ScriptsDir\bin", "$ScriptsDir\powershell") | foreach {
    if (!(Test-Path $_)) {
        $null = New-Item -Path $_ -ItemType Directory -Force
    }
}

$ModuleBaseUri = "https://raw.githubusercontent.com/pldmgg/misc-powershell/master/MyModules"
$ScriptsBaseUri = "https://raw.githubusercontent.com/pldmgg/misc-powershell/master/MyScripts"
@(
  "$ModuleBaseUri/BootstrapRemoteHost.psm1"
  "$ModuleBaseUri/MiniServeModule.psm1"
  "$ModuleBaseUri/TTYDModule.psm1"
  "$ScriptsBaseUri/Install-ZeroTier.ps1"
  ) | foreach {
    if (!(Test-Path "$ScriptsDir\powershell\$(Split-Path $_ -Leaf)")) {
        $null = Invoke-WebRequest -Uri $_ -OutFile "$ScriptsDir\powershell\$(Split-Path $_ -Leaf)"
    }
}

# IMPORTANT NOTE: If YOU are not the one to install SSH/SSHD on the remote Windows Machine using the above...
# Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/pldmgg/misc-powershell/master/MyScripts/Install-SSHD.ps1'))
# ...make sure you set powershell.exe as the default shell for SSHD on the remote host via:
# $PowerShellBinPath = $(Get-Command "powershell.exe").Source; Set-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value $PowerShellBinPath -ErrorAction Stop

$ScriptsDir = "C:\Scripts"
Import-Module "$ScriptsDir\powershell\BootstrapRemoteHost.psm1"
$NewComputerName = "HelenGym" # Kitchen NUC
$RemoteIPAddress = "192.168.2.82"
$RemoteUserName = "ttadmin"
$SSHUserAndHost = $RemoteUserName + "@" + $RemoteIPAddress
$SSHPrivateKeyPath = "C:\Users\ttadmin\.ssh\id_rsa_elukpc_to_helengym"
$SSHPublicKeyPath = $SSHPrivateKeyPath + ".pub"
Invoke-ScaffoldingOnRemoteHost -RemoteUserName $RemoteUserName -RemoteIPAddress $RemoteIPAddress

$SendKeyParams = @{
    RemoteUserName = $RemoteUserName
    RemoteIPAddress = $RemoteIPAddress
    SSHPrivateKeyPath = $SSHPrivateKeyPath
    SSHPublicKeyPath = $SSHPublicKeyPath
}
Send-SSHKeyToRemoteHost @SendKeyParams

# At this point, if there's any issue using "ssh -i $SSHPrivateKeyPath $SSHUserAndHost", you
# Probably just need to comment out the following lines at the bottom of C:\ProgramData\ssh\sshd_config...
# Match Group administrators
#       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys 
# ...and restart the sshd service via: Restart-Service sshd

# Set Execution Policy to RemoteSigned so that scripts created locally can run
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`""

# Set profile.ps1
$tempFileForProfile = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName())
<#
$profileContent = @'
# Clean up the PATH environment variable
$env:Path = ($env:Path -split ';' | Sort-Object | Get-Unique) -join ';'
$FinalPath = $env:Path.TrimEnd(';') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::Machine).TrimEnd(';') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::User).TrimEnd(';')
$env:Path = ($FinalPath -split ';' | Sort-Object | Get-Unique) -join ';'

# Clean up environment variables loading (or not) from various sources
$userEnvironmentVariables = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::User)
$machineEnvironmentVariables = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
$pwshEnvironmentVariables = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process)

$finalHashtable = @{}

foreach ($key in $userEnvironmentVariables.Keys) {
    $value = $userEnvironmentVariables[$key]
    if ($value -ne $machineEnvironmentVariables[$key] -and $value -ne $pwshEnvironmentVariables[$key]) {
        $finalHashtable[$key] = $value
    }
}

foreach ($key in $machineEnvironmentVariables.Keys) {
    $value = $machineEnvironmentVariables[$key]
    if ($value -ne $userEnvironmentVariables[$key] -and $value -ne $pwshEnvironmentVariables[$key]) {
        $finalHashtable[$key] = $value
    }
}

foreach ($key in $pwshEnvironmentVariables.Keys) {
    $value = $pwshEnvironmentVariables[$key]
    if ($value -ne $userEnvironmentVariables[$key] -and $value -ne $machineEnvironmentVariables[$key]) {
        $finalHashtable[$key] = $value
    }
}

# Set the cleaned up environment variables
foreach ($key in $finalHashtable.Keys) {
    $value = $finalHashtable[$key]
    [System.Environment]::SetEnvironmentVariable($key,$value)
}
'@
$profileContent | Out-File $tempFileForProfile -Encoding ascii
#>
$null = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pldmgg/misc-powershell/master/MyScripts/profile_2023.ps1" -OutFile $tempFileForProfile

# Set profile.ps1 for Windows PowerShell
$PSProfilePath = "C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1"
$PSProfilePath1 = "C:\Users\$RemoteUserName\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
$SCPRemoteLocationStringPSProfile = $RemoteUserName + '@' + $RemoteIPAddress + ':' + $PSProfilePath
$SCPRemoteLocationStringPSProfile1 = $RemoteUserName + '@' + $RemoteIPAddress + ':' + $PSProfilePath1
scp.exe -i $SSHPrivateKeyPath $tempFileForProfile $SCPRemoteLocationStringPSProfile
scp.exe -i $SSHPrivateKeyPath $tempFileForProfile $SCPRemoteLocationStringPSProfile1

# At this point, run ssh -i $SSHPrivateKeyPath $SSHUserAndHost at least once and accept the agreement
# This is because there's code in profile.ps1 that Install a Module from PSGallery
ssh -i $SSHPrivateKeyPath $SSHUserAndHost

# Enable ICMP Ping
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Set-NetFirewallRule -DisplayName 'File and Printer Sharing (Echo Request - ICMPv4-In)' -Enabled True`""

# Set Timezone
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Get-TimeZone -Id 'Eastern Standard Time' | Set-TimeZone`""

# Rename Computer
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Rename-Computer -NewName '$NewComputerName' -Restart`""

# Get LastBootTime to ensure that the machine has rebooted after renaming
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"(Get-CimInstance Win32_OperatingSystem).LastBootUpTime`""

# Install Pwsh
$PwshScriptPath = "$ScriptsDir\powershell\Install-Pwsh.ps1"
$SCPPwshRemoteLocationString = $RemoteUserName + '@' + $RemoteIPAddress + ':' + $PwshScriptPath
scp.exe -i $SSHPrivateKeyPath $PwshScriptPath $SCPPwshRemoteLocationString
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"& $PwshScriptPath`""
# Set Pwsh profile.ps1
$Pwsh7ProfilePath = 'C:\Program Files\PowerShell\7\profile.ps1'
$Pwsh7ProfilePath1 = "C:\Users\$RemoteUserName\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
$SCPRemoteLocationStringPwshProfile = $RemoteUserName + '@' + $RemoteIPAddress + ':' + "'" + $Pwsh7ProfilePath + "'"
$SCPRemoteLocationStringPwshProfile1 = $RemoteUserName + '@' + $RemoteIPAddress + ':' + $Pwsh7ProfilePath1
scp.exe -i $SSHPrivateKeyPath $tempFileForProfile $SCPRemoteLocationStringPwshProfile
scp.exe -i $SSHPrivateKeyPath $tempFileForProfile $SCPRemoteLocationStringPwshProfile1
# At this point, run ssh -i $SSHPrivateKeyPath $SSHUserAndHost and launch pwsh at least once
ssh -i $SSHPrivateKeyPath $SSHUserAndHost
# Optionally set the default sshd shell to pwsh in the registry.
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Set-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value ((Get-Command pwsh).Source); Restart-Service sshd`""
# NOTE: If you're going to use Invoke-Command/New-PSSession over ssh, then the below sshd_config subsystem changes are required
$SSHDConfigPath = "C:\ProgramData\ssh\sshd_config"
$PwshSubsystemString = "Subsystem powershell c:/progra~1/powershell/7/pwsh.exe -sshs -nologo"
$OverrideSubsystemsString = "# override default of no subsystems"
$RemoteSSHDConfig = ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Stop-Service sshd; if ((Get-Content '$SSHDConfigPath') -notcontains '$PwshSubsystemString') {(Get-Content '$SSHDConfigPath') -replace [Regex]::Escape('$OverrideSubsystemsString'), ('$OverrideSubsystemsString' + [Environment]::NewLine + '$PwshSubsystemString') | Set-Content '$SSHDConfigPath'}; Start-Service sshd; Get-Content '$SSHDConfigPath'`""

# Remove the tempfile
$null = Remove-item -Path $tempFileForProfile -Force

# Now you can use pwsh remoting commands like:
$PSSession = New-PSSession -HostName $RemoteIPAddress -UserName $RemoteUserName -IdentityFilePath $SSHPrivateKeyPath
$ArrayOfCimInstances = Invoke-Command $PSSession -ScriptBlock {Get-NetIPAddress -AddressFamily IPv4}

# Install ZeroTier
$ZTScriptPath = "$ScriptsDir\powershell\Install-ZeroTier.ps1"
$ZTNetworkID = 'id'
$ZTToken = 'token'
$SCPRemoteLocationString = $RemoteUserName + '@' + $RemoteIPAddress + ':' + $ZTScriptPath
scp.exe -i $SSHPrivateKeyPath $ZTScriptPath $SCPRemoteLocationString
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"& $ZTScriptPath -NetworkID $ZTNetworkID -Token $ZTToken`""

# Disable Bitlocker and Decrypt on ALL Volumes
#Disable-BitLocker -MountPoint (Get-BitLockerVolume) -Confirm:$false
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Disable-BitLocker -MountPoint (Get-BitLockerVolume) -Confirm:```$false`""

# Test to make sure that winget is working
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"winget search Microsoft.PowerShell`""
# If it's not working, reinstall it:
$Owner = "microsoft"
$Repo = "winget-cli"
$ReleaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest"
$Asset = $ReleaseInfo.assets | Where-Object {$_.Name -match "msixbundle"}
$AssetUrl = $Asset.browser_download_url
$AssetName = $Asset.Name
$AssetVersion = [version]$($AssetUrl.Split("/")[-2] -replace 'v','')
$DownloadPath = "$env:USERPROFILE\Downloads\$AssetName"
Invoke-WebRequest -Uri $AssetUrl -OutFile $DownloadPath -ErrorAction Stop
$MsixBundleRemotePath = "$ScriptsDir\bin\$AssetName"
$SCPRemoteLocationStringWinget = $RemoteUserName + '@' + $RemoteIPAddress + ':' + $MsixBundleRemotePath
scp.exe -i $SSHPrivateKeyPath $DownloadPath $SCPRemoteLocationStringWinget
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"dism.exe /Online /Add-ProvisionedAppxPackage /PackagePath:$MsixBundleRemotePath /SkipLicense`""
# Test to make sure it's working...again...
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"winget search Microsoft.PowerShell`""
# IMPORTANT NOTE: If it's still not working, or if winget ever gives you an error about "Data source", do the following:
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Invoke-WebRequest -Uri 'https://cdn.winget.microsoft.com/cache/source.msix' -OutFile 'C:\Scripts\bin\source.msix'; Add-AppxPackage 'C:\Scripts\bin\source.msix'; winget search nmap; winget --version`""
# IMPORTANT NOTE: To upgrade winget itself, do the following from Elevated PowerShell:
Invoke-RestMethod "https://raw.githubusercontent.com/pldmgg/misc-powershell/master/MyScripts/Upgrade-Winget.ps1" | Invoke-Expression


# Use winget to install pwsh, nmap, chrome, nomachine, vmware player, and hyper-v
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"winget install Microsoft.PowerShell`""
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"winget install nmap`""
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"winget install Google.Chrome`""
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"winget install NoMachine.NoMachine`""
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"winget install VMware.WorkstationPlayer`""
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart; Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All; Restart-Computer -Force`""

# Get LastBootTime to ensure that the machine has rebooted after enabling Hyper-V
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"(Get-CimInstance Win32_OperatingSystem).LastBootUpTime`""

# Install Chocolatey
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))`""
# Update Environment Variables to access Chocolatey bin path
#[Environment]::SetEnvironmentVariable('Path', ([Environment]::GetEnvironmentVariable('Path', 'Machine') + ';C:\ProgramData\chocolatey\bin'), 'Machine')
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"[Environment]::SetEnvironmentVariable('Path', (([Environment]::GetEnvironmentVariable('Path', 'Machine')).Trim(';') + ';C:\ProgramData\chocolatey\bin;C:\ProgramData\chocolatey\lib'), 'Machine')`""
#[Environment]::SetEnvironmentVariable('Path', ([Environment]::GetEnvironmentVariable('Path', 'User') + ';C:\ProgramData\chocolatey\bin'), 'User')
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"[Environment]::SetEnvironmentVariable('Path', (([Environment]::GetEnvironmentVariable('Path', 'User')).Trim(';') + ';C:\ProgramData\chocolatey\bin;C:\ProgramData\chocolatey\lib'), 'User')`""

# Use Chocolatey to install VSCode, nano and veeam-agent
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"choco install lockhunter -y`""
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"choco install vscode -y`""
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"choco install nano -y`""
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"choco install veeam-agent -y`""

# Restart the machine because a few of the above installs require a reboot
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Restart-Computer -Force`""

# Get LastBootTime to ensure that the machine has rebooted after installing veeam-agent
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"(Get-CimInstance Win32_OperatingSystem).LastBootUpTime`""

# Enable RDP
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0; Enable-NetFirewallRule -DisplayName 'Remote Desktop*'`""
# Disable RDP via
# ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 1; Disable-NetFirewallRule -DisplayName 'Remote Desktop*'`""

# IMPORTANT NOTE: For some reason the installer fails unless it thinks you're logged into a GUI session
# NOTE: If you haven't install Hyper-V features, do it NOW
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart; Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All; Restart-Computer -Force`""
mstsc /v:$RemoteIPAddress
# Enable WSL Feature
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
wsl --install
Restart-Computer -Force
# Download the latest Linux kernel update package from one of the following links:
https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi
OR
https://aka.ms/wsl2kernelmsix64
# Install the .msi package
msiexec.exe /i wsl_update_x64.msi /quiet
# Set WSL 2 as Default Version
wsl --set-default-version 2
Restart-Computer -Force
mstsc /v:$RemoteIPAddress
# Just wait for wsl to pop open a window to finish the install
# IMPORTANT NOTE: At this point, in order to get wsl to work from within an ssh session to the host machine...
# ...open the Windows "Settings" GUI and navigate Apps -> Installed Apps -> Search for "linux" -> Uninstall everything EXCEPT the Windows Subsystem for Linux Update
# The "Ubuntu" instance you already setup should still be fully configured with everything you've already done.
wsl
sudo apt update && sudo apt upgrade -y
sudo apt install openssh-server -y
sudo sed -i -E 's,^#?Port.*$,Port 2222,' /etc/ssh/sshd_config
sudo service ssh restart
sudo sh -c "echo '${USER} ALL=(root) NOPASSWD: /usr/sbin/service ssh start' >/etc/sudoers.d/service-ssh-start"
exit
# Now you should be back in powershell on the remote host within an RDP session
# Allow ssh traffic on port 2222
New-NetFirewallRule -Name wsl_sshd -DisplayName 'OpenSSH Server (sshd) for WSL' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 2222
# Now we want to create a scheduled task that will start WSL AND ssh within WSL on boot
$ScriptOutputPath = "C:\Scripts\bin\wsl_sshd.ps1"
$ScriptContentAsString = @'
# Set Log Info and WSL Instance Name
$LogFileDir = "C:\Scripts\logs"
$LogFilePath = $LogFileDir + '\' + 'start_wsl_sshd_' + $(Get-Date -Format MMddyy_hhmmss) + '.log'
$WslInstanceName = "Ubuntu"

# Start SSH service in WSL
try {
    #bash.exe -c "sudo /usr/sbin/service ssh start"
    wsl --distribution "$WslInstanceName" --user root /bin/sh -c "/usr/sbin/service ssh start"
} catch {
    $ErrMsg = $_.Exception.Message
    $null = Add-Content -Path $LogFilePath -Value $ErrMsg
    Write-Error $ErrMsg
    return
}

# Remove port proxy rule
try {
    netsh.exe interface portproxy delete v4tov4 listenport=2222 listenaddress=0.0.0.0 protocol=tcp
} catch {
    Write-Host "Continuing..."
}

# Get IP address from WSL
try {
    #$IP = (wsl.exe hostname -I).Trim()
    $IP = ((wsl --distribution "$WslInstanceName" --user root /bin/sh -c "ip addr show eth0 | grep 'inet ' | cut -d/ -f1") -split '[\s]')[-1].Trim()
} catch {
    $ErrMsg = $_.Exception.Message
    $null = Add-Content -Path $LogFilePath -Value $ErrMsg
    Write-Error $ErrMsg
    return
}

if (!$IP) {
    $null = Add-Content -Path $LogFilePath -Value 'Unable to identify wsl IP Address via: (wsl.exe hostname -I).Trim()'
    Write-Error $ErrMsg
    return
}

# Add port proxy rule with the obtained IP address
netsh.exe interface portproxy add v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=2222 connectaddress=$IP

'@
$TaskName = "Start WSL SSHD on Boot"
$TaskUser = "ttadmin"
$ScriptContentAsString | Out-File -FilePath $ScriptOutputPath -Encoding ascii -Force
$TenSecondsFromNow = $(Get-Date).Add($(New-TimeSpan -Seconds 10))
$TaskTrigger = New-ScheduledTaskTrigger -AtStartup
$Options = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit $(New-TimeSpan -Hours 1)
$Passwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Read-Host -Prompt "Enter password" -AsSecureString)))
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"& $ScriptOutputPath`""
Register-ScheduledTask -TaskName $TaskName -Trigger $TaskTrigger -Settings $Options -User $TaskUser -Password $Passwd -Action $Action -ErrorAction Stop
# If the Scheduled Task doesn't work for whatever reason, you can activate WSL SSH via:
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"& $ScriptOutputPath`""
# If you need to manually run the scheduled task in order to get ssh on WSL running, do the following:
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Get-ScheduledTask -TaskName '$TaskName' | Start-ScheduledTask`""
# And you should be able to connecto to WSL directly via:
ssh ttadmin@$RemoteIPAddress -p 2222

# IMPORTANT NOTE REGARDING LAUNCHING WSL DISTRO WHILE WITHIN HOST SSH SESSION:
- Use the following command format from within an ssh shell in order to avoid the error about the system not being able to access the file:
& 'C:\Program Files\WSL\wsl.exe' -d Ubuntu
& 'C:\Program Files\WSL\wsl.exe' -d kali-linux

# Optionally Install Windows Subsystem for Android
# DOESN'T WORK: ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"winget install --silent --exact --id=9P3395VX91NR -e --accept-package-agreements --accept-source-agreements`""
#Invoke-WebRequest -uri 'http://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/16f3fac4-75ab-484d-8e8a-fcbc560cd6df?P1=1697670694&P2=404&P3=2&P4=Ga0XxY8EJDPWIghjDv7XAVoN1mGMZORbpsHBpLzwUS032OvgcSa8nNRWELa5bzch%2fwg3oJFPlQ2iuoCJbrMERQ%3d%3d' -OutFile 'C:\Users\ttadmin\Downloads\windows_subsystem_for_android.msixbundle'
#dism.exe /Online /Add-ProvisionedAppxPackage /PackagePath:C:\Users\ttadmin\Downloads\windows_subsystem_for_android.msixbundle /SkipLicense
# NOTE: If the below $AppxUri doesn't work, you can get the latest version by navigating to https://store.rg-adguard.net/ and in the URL box, input: www.microsoft.com/en-us/p/windows-subsystem-for-android/9p3395vx91nr 
$AppxUri = 'http://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/16f3fac4-75ab-484d-8e8a-fcbc560cd6df?P1=1697670694&P2=404&P3=2&P4=Ga0XxY8EJDPWIghjDv7XAVoN1mGMZORbpsHBpLzwUS032OvgcSa8nNRWELa5bzch%2fwg3oJFPlQ2iuoCJbrMERQ%3d%3d'
$OutFilePath = 'C:\Users\ttadmin\Downloads\windows_subsystem_for_android.msixbundle'
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "pwsh.exe -ExecutionPolicy Bypass -Command `"Invoke-WebRequest -uri '$AppxUri' -OutFile '$OutFilePath'; dism.exe /Online /Add-ProvisionedAppxPackage /PackagePath:$OutFilePath /SkipLicense`""
# IMPORTANT NOTE: If none of the above works, just get it from here:
https://github.com/MustardChef/WSABuilds
# Launch Windows Subsystem for Android, go to "Advanced settings", turn on "Developer mode", click "Manage developer settings". This will launch...
# a GUI for the Android VM in the Settings menu called "Developer options". In "Developer options", turn on "USB debugging."
# Still while the "Developer options" window is open, in the Windows host terminal (powershell), run: .\adb.exe connect 127.0.0.1:58526
# This will pop open a window on the Android VM that asks if you can trust the device. Check the checkbox always and answer in the affirmative.
# Download F-Droid from https://f-droid.org/en/packages/org.fdroid.fdroid/
# In the Windows host terminal (powershell), make sure you are connected to 127.0.0.1:58526 via: .\adb.exe devices
# Install F-Droid via: .\adb.exe install D:\ttadmin_Downloads\F-Droid.apk
# F-Droid should show up in the Windows Start Menu under "Recently added". You can also launch by using the shortcut under: C:\Users\ttadmin\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\
# Or you can launch directly in terminal via: C:\Users\ttadmin\AppData\Local\Microsoft\WindowsApps\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\WsaClient.exe /launch wsa://org.fdroid.fdroid
# In F-Droid, install the Aurora Store app, or download the Aurora Store .apk from https://gitlab.com/AuroraOSS/AuroraStore/-/releases and install it via: .\adb.exe install 'D:\ttadmin_Downloads\com.aurora.store_51.apk'
# IMPORTANT NOTE: You can launch the normal Android Settings menu via: .\adb.exe shell am start -n com.android.settings/.Settings\$WifiSettingsActivity
# IMPORTANT NOTE: You can check the IP Address of the Android VM by going to "About device".
# IMPORTANT NOTE: The network interface that WSA uses usually has an InterfaceAlias called "vEthernet (WSLCore)"
# Use this website to determine if the IP Address in "About device" falls within the subnet of the "vEthernet (WSLCore)" using CIDR notation: https://tehnoblog.org/ip-tools/ip-address-in-cidr-range/
# If WSA appears to have problems connecting to the internet, restarting the Windows host usually solves this

# Install TTYD and create scheduled task to run it as a specific user (i.e. the person who uses the PC most often)
$TaskUser = "ttadmin"
$CreateRemoteSchdTaskParams = @{
    RemoteUserName = $RemoteUserName
    RemoteIPAddress = $RemoteIPAddress
    ModuleDir = "C:\Scripts\powershell"
    SSHPrivateKeyPath = $SSHPrivateKeyPath
    NetworkInterfaceAlias = "ZeroTier One [$ZTNetworkID]"
    TaskUser = $TaskUser # Windows Account Username
    TaskUserPasswd = 'Unsecure321!' # Windows Account Password for the TaskUser account
    TTYDWebUser = "ttydadmin" # Basic Auth Username for TTYD Website
    TTYDWebPassword = "Unsecure321!" # Basic Auth Password for TTYD Website
}
Create-RemoteTTYDScheduledTask @CreateRemoteSchdTaskParams
# Run TTYD via running the Scheduled Task
$TaskName = "Run TTYD as $TaskUser"
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Start-ScheduledTask -TaskName '$TaskName'`""
# Kill TTYD via:
ssh -i $SSHPrivateKeyPath $SSHUserAndHost "powershell.exe -ExecutionPolicy Bypass -Command `"Stop-ScheduledTask -TaskName '$TaskName'; Stop-Process -Name ttyd -Force -ErrorAction SilentlyContinue`""


# Optionally, prompt the remote user for a secure string
Import-Module "$ScriptsDir\powershell\MiniServeModule.psm1"
# Make sure you have miniserve.exe on the local workstation
$NetworkInterfaceAlias = "ZeroTier One [$ZTNetworkID]"
Install-MiniServe -NetworkInterfaceAlias $NetworkInterfaceAlias
$PromptSSParams = @{
    RemoteUserName = $RemoteUserName
    RemoteIPAddress = $RemoteIPAddress
    SSHPrivateKeyPath = $SSHPrivateKeyPath
    MiniServeNetworkInterfaceAlias = $NetworkInterfaceAlias
    RemovePwdFile = $False
}
$UserString = Prompt-ActiveUserForSecureString @PromptSSParams


# Scan for Printers on Network
$printers = 1..254 | ForEach-Object {
    $ip = "192.168.5.$_"
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $result = $tcpClient.BeginConnect($ip, 9100, $null, $null)

    if ($result.AsyncWaitHandle.WaitOne(1000, $false) -and $tcpClient.Connected) {
        $tcpClient.Close()
        [PSCustomObject]@{
            IP = $ip
            Status = 'Printer Found'
        }
    } else {
        $tcpClient.Close()
        $null
    }
} | Where-Object { $_.Status -eq 'Printer Found' }


# Kali Linux via WSL2
# Reference: https://www.kali.org/docs/wsl/wsl-preparations/
# Install kali-linux via wsl
wsl --install --distribution kali-linux
- Run `kali` to finish the initial setup of creating a new user
wsl -d kali-linux
# Now within kali-linux shell:
sudo apt update && sudo apt upgrade -y
sudo apt install -y kali-win-kex
# Start kali-linux in Windowed Mode (verified working):
wsl -d kali-linux kex --win -s
# Start kali-linux in Seamless Mode (doesn't work consistently):
wsl -d kali-linux kex --sl
$WslInstanceName = "kali-linux"
$IP = ((wsl --distribution "$WslInstanceName" --user root /bin/sh -c "ip addr show eth0 | grep 'inet ' | cut -d/ -f1") -split '[\s]')[-1].Trim()
# View Kali Desktop via VNC
winget install TigerVNC
- Add C:\Program Files\TigerVNC to User and System/Machine PATH
vncviewer.exe "$IP`:5901"
# Optionally Expose the VNC Port to the LAN
New-NetFirewallRule -Name kali_vnc -DisplayName 'Kali Linux on WSL via VNC' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5901
netsh.exe interface portproxy delete v4tov4 listenport=5901 listenaddress=0.0.0.0 protocol=tcp
netsh.exe interface portproxy add v4tov4 listenport=5901 listenaddress=0.0.0.0 connectport=5901 connectaddress=$IP