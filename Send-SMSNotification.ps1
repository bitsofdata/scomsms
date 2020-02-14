#------------------------------------------------------------------------------
# AUTHOR: Jason McReynolds
# VERSION: 1.2
# DATE: 8/28/2014
# NAME: Send-SMSNotification.ps1
# COMMENT: Script to send an SMS notification from a SCOM Command Channel via
#		   the MultiTech MultiModem iSMS Server
# Update: 8/22/2014	v1.1	- Added log file management
# Update: 8/28/2014	v1.2	- Removed unused parameters and added some comments
#
# SCOM Command Channel Setup:
#	Full path of the command file:
#	C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
#
#	Command line parameters:
#	-Command "& '"<path to this file>\Send-SMSNotification.ps1"'" -subscriptionID '$MPElement$' -alertID '$Data/Context/DataItem/AlertId$'
#
#	Startup folder for the command line:
#	<Directory where this file is located>
#
# Usage (for testing): .\Send-SMSNotification.ps1 -subscriptionID "<Subscription ID Here>"  -alertID "<Alert ID Here>"
#------------------------------------------------------------------------------
param([string]$alertID,[string]$subscriptionID)

# Setup variables
$logFileBaseDir = "<LogFileBaseDirectory>"
$logFileName = "SMSNotificationLog_$(date -f  MM-dd-yyyy).log"
$logFilePath = Join-Path -path $logFileBaseDir -childpath $logFileName
# variable to delete log files older than X days
$logsOlderThan = 30
$dateInfo = Get-Date
$SCOMServer = $env:computername
# Enter Username and Password for iSMS user in order to connect and send SMS messages
$user = "<iSMSUserName>"
$password = "<iSMSUserPassword"

# Import Operations Manager PowerShell module
Import-Module OperationsManager
New-SCOMManagementGroupConnection -ComputerName $SCOMServer

$alertDetails = Get-SCOMAlert -ID $alertID
$subscriptionInfo = get-scomnotificationsubscription -id $subscriptionID

# Output alert info to log file for tracking purposes
$result = "$($dateInfo): alertID: $($alertID), subscriptionID: $($subscriptionID), Subscription DisplayName: $($subscriptionInfo.DisplayName), MonitoringObjectDisplayName: $($alertDetails.MonitoringObjectDisplayName), Name: $($alertDetails.Name), Description: $($alertDetails.UnformattedDescription)"
$result | Out-File -FilePath $logFilePath -Append

# Get a list of the recipients for the subscription
$toRecipients = $subscriptionInfo.ToRecipients
# Get a list of the configured devices used for alerting for the subscribers
$configuredDevices = $toRecipients.Devices
## Check the protocol and the Address for the device to get the phone numbers that start with +1
foreach ($phone in $configuredDevices)
{
	if($phone.Protocol -eq "SMS" -and $phone.Address.StartsWith("+1"))
	{
		write-output "$($dateInfo): alertID: $($alertID), Send SMS message to: $($phone.Name), number: $($phone.Address)" | Out-File -FilePath $logFilePath -Append
		$messageText = "$($alertDetails.MonitoringObjectDisplayName) * $($alertDetails.UnformattedDescription) * $($alertDetails.Name)"
		## System.Web.HttpUtility does not work since it puts in a + instead of %20 for spaces. Use System.Uri instead.
		## http://serialseb.blogspot.com/2008/03/httputilityurlencode-considered-harmful.html
		$encodedURL = [System.Uri]"http://10.32.17.10:81/sendmsg?user=$($user)&passwd=$($password)&cat=1&priority=3&modem=1&to=$($phone.Address)&text=$($messageText)" | select AbsoluteUri
		write-output "$($dateInfo): alertID: $($alertID), SMS URL: $($encodedURL.AbsoluteUri)" | Out-File -FilePath $logFilePath -Append
		$r = [System.Net.WebRequest]::Create($encodedURL.AbsoluteUri)
		$resp = $r.GetResponse()
		$reqstream = $resp.GetResponseStream()
		$sr = new-object System.IO.StreamReader $reqstream
		$result = $sr.ReadToEnd()
		write-output "$($dateInfo): alertID: $($alertID), Connection result: $($result)" | Out-File -FilePath $logFilePath -Append
	}
}

# Clean up old log files
# From: http://www.networknet.nl/apps/wp/published/powershell-delete-files-older-than-x-days
# and http://stackoverflow.com/questions/17829785/delete-files-older-than-15-days-using-powershell
$Extension = "*.log"
$LastWrite = $dateInfo.AddDays(-$logsOlderThan)

$Files = Get-Childitem $logFileBaseDir -Include $Extension -Recurse | Where {!$_.PSIsContainer -and $_.LastWriteTime -lt "$LastWrite"}

foreach ($File in $Files) 
    {
    if ($File -ne $NULL)
        {
        write-output "$($dateInfo): Deleting File $File" | Out-File -FilePath $logFilePath -Append
        Remove-Item $File.FullName | out-null
        }
    }
