configuration CreateADPDC 
{ 
   param 
   ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount=5,
        [Int]$RetryIntervalSec=10
    ) 
    
    Import-DscResource -ModuleName xActiveDirectory, xNetworking, PSDesiredStateConfiguration, xPendingReboot
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)

    Set-Culture nb-NO
    Set-WinSystemLocale nb-NO
    Set-WinHomeLocation -GeoId 177
    Set-WinUserLanguageList nb -Force

    Get-ChildItem -path HKLM:\SYSTEM\CurrentControlSet\Services\ -Recurse | where { $_.Name -match 'OneSyncSvc' -and $_.PSParentPath -eq "Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services"} | Set-ItemProperty -Name Start -Value 4
    Set-Service MapsBroker -StartupType Manual
	
	function Set-Recovery{
		param
		(
			[string] [Parameter(Mandatory=$true)] $ServiceDisplayName,
			[string] [Parameter(Mandatory=$true)] $Server,
			[string] $action1 = "restart",
			[int] $time1 =  30000, # in miliseconds
			[string] $action2 = "restart",
			[int] $time2 =  30000, # in miliseconds
			[string] $actionLast = "restart",
			[int] $timeLast = 30000, # in miliseconds
			[int] $resetCounter = 4000 # in seconds
		)
		$serverPath = "\\" + $server
		$services = Get-CimInstance -ClassName 'Win32_Service' | Where-Object {$_.DisplayName -imatch $ServiceDisplayName}
		$action = $action1+"/"+$time1+"/"+$action2+"/"+$time2+"/"+$actionLast+"/"+$timeLast

		foreach ($service in $services){
			# https://technet.microsoft.com/en-us/library/cc742019.aspx
			$output = sc.exe $serverPath failure $($service.Name) actions= $action reset= $resetCounter
		}
	}
	
	Set-Recovery -ServiceDisplayName "Volume Shadow Copy" -Server .
	Set-Recovery -ServiceDisplayName "IaaSVmProvider" -Server .
    
    #cd "c:\SQLServerFull"
    #Setup /QUIET /ACTION=REBUILDDATABASE /INSTANCENAME=MSSQLSERVER /SQLSYSADMINACCOUNTS=$DomainName\$Admincreds.UserName /SAPWD=$Admincreds.Password /SQLCOLLATION=Danish_Norwegian_CI_AS

    Node localhost
    {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
        }

	WindowsFeature DNS { 
            Ensure = "Present" 
            Name = "DNS"		
        }

	WindowsFeature DnsTools {
	    Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
	}

        xDnsServerAddress DnsServerAddress { 
            Address = '127.0.0.1' 
            InterfaceAlias = $InterfaceAlias
            AddressFamily = 'IPv4'
	    DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature ADDSInstall { 
            Ensure = "Present" 
            Name = "AD-Domain-Services"
	    DependsOn="[WindowsFeature]DNS" 
        } 

        WindowsFeature ADDSTools {
            Ensure = "Present"
            Name = "RSAT-ADDS-Tools"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature ADAdminCenter {
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }
         
        xADDomain FirstDS {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DependsOn = "[WindowsFeature]ADDSInstall"
        }
    }
} 