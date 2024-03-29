<#
.SYNOPSIS
  This is a summary of what the script is.
.DESCRIPTION
  This is a detailed description of what the script does and how it is used.
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER vcenter
  VMware vCenter server hostname. Default is localhost. You can specify several hostnames by separating entries with commas.
.EXAMPLE
  Connect to a vCenter server of your choice:
  PS> .\template.ps1 -vcenter myvcenter.local
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Stephane Bourdeaud (sbourdeaud@nutanix.com)
  Revision: September 26th 2016
#>

#Region Parameters
######################################
##   parameters and initial setup   ##
######################################
#let's start with some command line parsing
Param
(
    #[parameter(valuefrompipeline = $true, mandatory = $true)] [PSObject]$myParam1,
    [parameter(mandatory = $false)] [switch]$help,
    [parameter(mandatory = $false)] [switch]$history,
    [parameter(mandatory = $false)] [switch]$log,
    [parameter(mandatory = $false)] [switch]$debugme,
    [parameter(mandatory = $false)] [string]$vcd,
	[parameter(mandatory = $false)] [string]$type,
	[parameter(mandatory = $false)] [string]$name,
	[parameter(mandatory = $false)] [switch]$all
)
#EndRegion

#Region Functions
########################
##   main functions   ##
########################

#this function is used to output log data
Function OutputLogData 
{
	#input: log category, log message
	#output: text to standard output
<#
.SYNOPSIS
  Outputs messages to the screen and/or log file.
.DESCRIPTION
  This function is used to produce screen and log output which is categorized, time stamped and color coded.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER myCategory
  This the category of message being outputed. If you want color coding, use either "INFO", "WARNING", "ERROR" or "SUM".
.PARAMETER myMessage
  This is the actual message you want to display.
.EXAMPLE
  PS> OutputLogData -mycategory "ERROR" -mymessage "You must specify a cluster name!"
#>
	param
	(
		[string] $category,
		[string] $message
	)

    begin
    {
	    $myvarDate = get-date
	    $myvarFgColor = "Gray"
	    switch ($category)
	    {
		    "INFO" {$myvarFgColor = "Green"}
		    "WARNING" {$myvarFgColor = "Yellow"}
		    "ERROR" {$myvarFgColor = "Red"}
		    "SUM" {$myvarFgColor = "Magenta"}
	    }
    }

    process
    {
	    Write-Host -ForegroundColor $myvarFgColor "$myvarDate [$category] $message"
	    if ($log) {Write-Output "$myvarDate [$category] $message" >>$myvarOutputLogFile}
    }

    end
    {
        Remove-variable category
        Remove-variable message
        Remove-variable myvarDate
        Remove-variable myvarFgColor
    }
}#end function OutputLogData

# Configure session to accept untrusted SSL certs
function ignoreSSL {
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

#connect to a vCD server
function connectVcd {
<#
.SYNOPSIS
  .
.DESCRIPTION
  This function is used to .
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER dummy1
  This the .
.PARAMETER dummy2
  This is the .
.EXAMPLE
  
#>
	param
	(
		[string] $Vcd,
		[System.Management.Automation.PSCredential] $Credentials
	)
	
    begin {
	}#end begin
	process {
		OutputLogData -category "INFO" -message "Connecting to the vCloud Director instance $Vcd..."
		if (!$myvarVcdConnect.IsConnected) {
			try {
				$myvarVcdConnect = Connect-CIServer -Server $Vcd -Org 'system' -Credential $Credentials -ErrorAction Stop
			}
			catch {
				OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
				OutputLogData -category "ERROR" -message "Could not connect to the vCloud Director $Vcd (credentials correct?), exiting."
				Remove-Variable * -ErrorAction SilentlyContinue
				$ErrorActionPreference = "Continue"
				Exit
			}
		}#endif connected?
		OutputLogData -category "INFO" -message "Connected to the vCloud Director $Vcd : OK"
	}#end process
	end {
		Remove-Variable Vcd
		Remove-Variable Credentials
		return $myvarVcdConnect
	}#end
}#end function


#EndRegion

#Region Variables
#initialize variables
	#misc variables
	$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
	$myvarvCenterServers = @() #used to store the list of all the vCenter servers we must connect to
	$myvarOutputLogFile = (Get-Date -UFormat "%Y_%m_%d_%H_%M_")
	$myvarOutputLogFile += "OutputLog.log"
	
	############################################################################
	# command line arguments initialization
	############################################################################	
	#let's initialize parameters if they haven't been specified
	if (!$vcd) {$vcd = read-host "Enter the hostname or IP address of the vCD instance"}
	if (!$type) {$type = read-host "What type of vCD object do you want to query?"}
	if (!$name -and !$all) {$name = read-host "Enter the name of the $type to query"}
	
	#Static Variables
	
#EndRegion

#Region Prep-work

# get rid of annoying error messages
if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}

#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 09/22/2016 sb   Initial release.
################################################################################
'@
$myvarScriptName = ".\script.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}

#let's make sure the VIToolkit is being used
if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
. “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” | Out-Null
} 

#EndRegion

#Region Processing
	#########################
	##   main processing   ##
	#########################
	
	#Region Connect2vCD
	OutputLogData -category "INFO" -message "Ignoring invalid ssl certificates..."
	IgnoreSSL  #let's ignore invalide SSL certificates
	if (!$credentials) {$credentials = Get-Credential -Message "Please enter the vCD credentials"}
    #connect to target vcd
	$myvarVcd = connectVcd -Credentials $credentials -Vcd $vcd
	#EndRegion
	
	#Region if -all
	if ($all) {
		OutputLogData -category "INFO" -message "Retrieving all $type..."
		#Region OrgVdc
		if ($type -eq "OrgVdc") {
			$myvarOrgVdcs = Get-OrgVdc
			foreach ($myvarOrgVdc in $myvarOrgVdcs) {
				OutputLogData -category "INFO" -message "Processing $($myvarOrgVdc.Name)..."
				$myvarUrl = $myvarOrgVdc.Href
				$myvarHeaders = @{"Accept"="application/*+xml;version=5.5"}
				$myvarHeaders += @{"x-vcloud-authorization"=$myvarVcd.SessionId}
				
				$myvarResponse = Invoke-RestMethod -Uri $myvarUrl -Headers $myvarHeaders -Method Get
				OutputLogData -category "INFO" -message "Exporting $($myvarOrgVdc.Name) configuration..."
				$myvarResponse | Export-Clixml .\$($myvarOrgVdc.Name).xml
			}
		
		}#endif OrgVdc
		#EndRegion
		#Region OrgVdcNetwork
		elseif ($type -eq "OrgVdcNetwork") {
			$myvarOrgVdcNetworks = Get-OrgVdcNetwork
			foreach ($myvarOrgVdcNetwork in $myvarOrgVdcNetworks) {
				OutputLogData -category "INFO" -message "Processing $($myvarOrgVdcNetwork.Name)..."
				$myvarUrl = $myvarOrgVdcNetwork.Href
				$myvarHeaders = @{"Accept"="application/*+xml;version=5.5"}
				$myvarHeaders += @{"x-vcloud-authorization"=$myvarVcd.SessionId}
				
				$myvarResponse = Invoke-RestMethod -Uri $myvarUrl -Headers $myvarHeaders -Method Get
				OutputLogData -category "INFO" -message "Exporting $($myvarOrgVdcNetwork.Name) configuration..."
				$myvarResponse | Export-Clixml .\$($myvarOrgVdcNetwork.Name).xml
			}
		}#endif OrgVdcNetwork
		#EndRegion
		#Region All other object types
		else {
			#Search
			try {
			$myvarObjects = Search-Cloud -QueryType $type -ErrorAction Stop
			} catch {
			[System.Windows.Forms.MessageBox]::Show("Exception: " + $_.Exception.Message + " - Failed item:" + $_.Exception.ItemName ,"Error.",0,[System.Windows.Forms.MessageBoxIcon]::Exclamation)
			OutputLogData -category "ERROR" -message "Could not retrieve any $type"
			Exit
			}

			#let's process each edge gateway
			foreach ($myvarObject in $myvarObjects)
			{
				$myvarObjectView = $myvarObject | Get-CIView
				$myvarObjectName = $myvarObject.Name
				OutputLogData -category "INFO" -message "Processing $myvarObjectName..."
				OutputLogData -category "INFO" -message "Setting up connection to REST API..."
				$myvarWebclient = New-Object system.net.webclient
				$myvarWebclient.Headers.Add("x-vcloud-authorization",$myvarObjectView.Client.SessionKey)
				$myvarwebclient.Headers.Add("accept",$myvarObjectView.Type + ";version=5.1")
				OutputLogData -category "INFO" -message "Retrieving $type details..."
				[XML]$myvarObjectXML = $myvarwebclient.DownloadString($myvarObjectView.href)
				
				OutputLogData -category "INFO" -message "Exporting $myvarObjectName..."
				$myvarObjectXML | Export-Clixml .\$myvarObjectName.xml
			}#end foreach object
		}#end else OrgVdc
		#EndRegion
	}#endif all
	#EndRegion
	#Region process individual object
	else {
		OutputLogData -category "INFO" -message "Searching for $type $name..."
		if ($type -eq "OrgVdc")
		{
			$myvarOrgVdc = Get-OrgVdc -Name $name
			$myvarUrl = $myvarOrgVdc.Href
			$myvarHeaders = @{"Accept"="application/*+xml;version=20.0"}
			$myvarHeaders += @{"x-vcloud-authorization"=$myvarVcd.SessionId}
			
			$myvarResponse = Invoke-RestMethod -Uri $myvarUrl -Headers $myvarHeaders -Method Get
			$myvarResponse | Export-Clixml .\$($myvarOrgVdc.Name).xml
		}#endif OrgVdc
		elseif ($type -eq "OrgVdcNetwork") {
			$myvarOrgVdcNetworks = Get-OrgVdcNetwork -Name $name
			foreach ($myvarOrgVdcNetwork in $myvarOrgVdcNetworks) {
				OutputLogData -category "INFO" -message "Processing $($myvarOrgVdcNetwork.Name)..."
				$myvarUrl = $myvarOrgVdcNetwork.Href
				$myvarHeaders = @{"Accept"="application/*+xml;version=5.5"}
				$myvarHeaders += @{"x-vcloud-authorization"=$myvarVcd.SessionId}
				
				$myvarResponse = Invoke-RestMethod -Uri $myvarUrl -Headers $myvarHeaders -Method Get
				OutputLogData -category "INFO" -message "Exporting $($myvarOrgVdcNetwork.Name) configuration..."
				$myvarResponse | Export-Clixml .\$($myvarOrgVdcNetwork.Name).xml
			}
		}#endif OrgVdcNetwork
		else
		{
			#Search object
			try {
			$myvarObjectView = Search-Cloud -QueryType $type -Name $name -ErrorAction Stop | Get-CIView
			} catch {
			[System.Windows.Forms.MessageBox]::Show("Exception: " + $_.Exception.Message + " - Failed item:" + $_.Exception.ItemName ,"Error.",0,[System.Windows.Forms.MessageBoxIcon]::Exclamation)
			OutputLogData -category "ERROR" -message "$type with name $name not found"
			Exit
			}
			
			OutputLogData -category "INFO" -message "Setting up connection to REST API..."
			$myvarWebclient = New-Object system.net.webclient
			$myvarWebclient.Headers.Add("x-vcloud-authorization",$myvarObjectView.Client.SessionKey)
			$myvarwebclient.Headers.Add("accept",$myvarObjectView.Type + ";version=5.1")
			OutputLogData -category "INFO" -message "Retrieving $type details..."
			[XML]$myvarObjectXML = $myvarwebclient.DownloadString($myvarObjectView.href)
			OutputLogData -category "INFO" -message "Exporting to xml file..."
			$myvarObjectXML | Export-Clixml .\$name.xml
		}#end else orgvdc
		
		
	}#endif else all
	#EndRegion
	
	
#EndRegion

#Region Cleanup
#########################
##       cleanup       ##
#########################
	
	#disconnect from the vCD instance
	OutputLogData -category "INFO" -message "Disconnecting from vCloud Director instance $vcd..."
	Disconnect-CIServer -Server $vcd -Confirm:$false
	
	#let's figure out how much time this all took
	OutputLogData -category "SUM" -message "total processing time: $($myvarElapsedTime.Elapsed.ToString())"
	
	#cleanup after ourselves and delete all custom variables
	Remove-Variable * -ErrorAction "SilentlyContinue"
	$ErrorActionPreference = "Continue"
#EndRegion