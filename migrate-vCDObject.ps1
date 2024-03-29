<#
.SYNOPSIS
  This script is used to migrate vCloud Director objects from one vCD instance to another. It can read from XML files, or directly from a vCD instance.  Objects can be migrated individually, or in bulk (by migrating Organizations).  Please read the full description for limitations.
.DESCRIPTION
  The following objects can be migrated with this script: External Networks, Organizations, Users (passwords will need to be reset) and Roles, OrgVdcs, Edge Gateways (and their service configuration), OrgVdc Networks.
  The following objects and attributes are NOT migrated: Catalogs, Catalog Items, vApps (and their associated objects such as vApp Networks).  Metadata is NOT migrated for any object.
  The script has the following limitations:
  (1)when importing Organizations, there can be only one EdgeGateway per OrgVdc.  If that is not the case, you will need to migrate Edge Gateways one by one before being able to finish an Organization migration.
  (2)external networks must be individually migrated first, or Edge Gateways will not be migrated.
  (3)when importing Organizations, all child objects are attempted to be created.  This is not true for any other object type.
  (4)this script has only been tested with a vCD 5.6 as source and vCD 8.10 as target.
  (5)if objects already exist, the script just skips creation.  It will NOT delete the object and re-create it.  The only exception is when re-applying EdgeGateway services configuration with the -gwservices parameter.
  (6)when migrating an OrgVdc, the *any storage policy must exist on the ProviderVdc.
  (7)when migrating an Organization from a source vCD instance, all supported child objects will be created automatically.  When migrating from XML with -import, only the Organization object is created.
  The script will prompt you for any required parameters.  If you want to import from XML, you will need to specify -import.
.PARAMETER help
  Displays a help message (seriously, what did you think this was?)
.PARAMETER history
  Displays a release history for this script (provided the editors were smart enough to document this...)
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER sourcevcd
  FQDN or IP address of the source vCloud Director instance from which objects will be read.
.PARAMETER targetvcd
  FQDN or IP address of the target vCloud Director instance to which objects will be written.
.PARAMETER import
  Full path to the XML file describing the object you want to migrate/import to the target vCD instance. This is exclusive with sourcevcd; use either but not both.  XML file can be a vCD object export (using the REST API) or a properly formatted XML file as documented in the vCD REST API documentation.
.PARAMETER objecttype
  This is only required with sourcevcd.  It specifies the type of object you are trying to migrate.  This can be Organization, OrgVdc, ExternalNetwork, AdminUser, OrgVdcNetwork or EdgeGateway.
.PARAMETER objectname
  This is the name of the object you are trying to migrate as displayed on the source vCD instance (exp: the organization name).
.PARAMETER gwservices
  Use this switch if you want to apply EdgeGateway services configuration only and not create the whole EdgeGateway object.
.PARAMETER userpassword
  Specify a default password here which will be used for any AdminUser object migrated.  This is useful when imigrating Organizations which have multiple users. If you do not specify this, you will be prompted for a new password for each user that is migrated.
.PARAMETER rename
  Specifies that you want to rename objects.  Applies only if you are importing an organization from a source vCD instance, and will prompt you to rename the following objects: organization, orgVdc and Edge Gateway.
.PARAMETER NewOrgName
  When using -rename, specifies the new name of the Organization object.
.PARAMETER NewOrgVdcName
  When using -rename, specifies the new name of the OrgvDC object.
.PARAMETER NewEdgeName
  When using -rename, specifies the new name of the Edge Gateway object.
.PARAMETER pvDC
  Specifies the name of the Provider vDC you want to use for the OrgVdc when importing an entire Organization structure from a source vCD instance.
.EXAMPLE
  Import an Organization from a source vCD:
  PS> .\migrate-vCDObject.ps1 -sourcevcd vcloud1.acme.com -targetvcd vcloud2.acme.com -objectType Organization -objectName AcmeCorp  -userPassword "AcmeCorp/4u"
.EXAMPLE
  Import an EdgeGateway from an XML file:
  PS> .\migrate-vCDObject.ps1 -targetvcd vcloud2.acme.com -import ".\AcmeCorp\Edge Gateways\AcmeCorp-Edge.xml"
.EXAMPLE
  Only re-apply the EdgeGateway service configuration from a source vCD:
  PS> .\migrate-vCDObject.ps1 -sourcevcd vcloud1.acme.com -targetvcd vcloud2.acme.com -objectType EdgeGateway -objectName AcmeCorp-Edge  -gwservices
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Stephane Bourdeaud (stephane.bourdeaud@nutanix.com)
  Revision: November 17th 2016
#>

#region Parameters
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
    [parameter(mandatory = $false)] [string]$sourcevcd,
	[parameter(mandatory = $false)] [string]$targetvcd,
	[parameter(mandatory = $false)] [string]$import,
	[parameter(mandatory = $false)] [string]$objectType,
	[parameter(mandatory = $false)] [string]$objectName,
	[parameter(mandatory = $false)] [switch]$gwservices,
	[parameter(mandatory = $false)] [string]$userPassword,
	[parameter(mandatory = $false)] [switch]$rename,
    [parameter(mandatory = $false)] [string]$newOrgName,
    [parameter(mandatory = $false)] [string]$newOrgVdcName,
    [parameter(mandatory = $false)] [string]$newEdgeName,
    [parameter(mandatory = $false)] [string]$pvDC
)
#endregion

#region Functions
########################
##   main functions   ##
########################

#this function is used to output log data
Function OutputLogData {
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
	[CmdletBinding()]
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

#figure out a REST URL
function getRESTURL {
	#input: lookup, rel, type, sessionId, object
	#output: Url string
<#
.SYNOPSIS
  Use this function to lookup REST Urls from a vCloud Director instance.
.DESCRIPTION
  The function uses a lookup source Url and looks in the Link section of the REST response to identify a specific Url matching a given rel and type.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER lookup
  This the lookup Url (as specified in the vCD REST API documentation).
.PARAMETER rel
  This is the rel you want to lookup.
.PARAMETER type
  This is the type you want to lookup.
.PARAMETER sessionId
  This is the sessionId you want to use for the REST lookup.
.PARAMETER object
  This is the type of object returned by the lookup URL within which we will examine the Link section for the given rel and type.
.EXAMPLE
  Lookup the Url for adding organizations using a sessionId from an object which is the result of the Connect-CiServer cmdlet:
  getRESTUrl -lookup "https://vcloud.local/api/admin") -type "application/vnd.vmware.admin.organization+xml" -rel "add" -sessionId $vcdConnect.SessionId -Object VCloud
#>
	[CmdletBinding()]
	#region param
	param
	(
		[string] $Lookup,		#this is the URL used to lookup the next URL (from documentation)
		[string] $Rel,			#this is the Rel type (add, delete, etc; also specified in the documentation)		
		[string] $Type,			#this is the content type (again, see the documentation)
		[string] $SessionId,	#this is the web session Id to use to perform the lookup
		[string] $Object		#this is the type of object we're looking into
	)
	#endregion
	
    begin {
		#prepare headers for our lookup request
		$RESTHeaders = @{"Accept"="application/*+xml;version=20.0"}
		$RESTHeaders += @{"x-vcloud-authorization"=$SessionId}
	}#end begin
	process {
		#get the XML from the lookup URL
		OutputLogData -category "INFO" -message "Accessing URL $Lookup..."
		try {
			$myvarRESTResponse = Invoke-RestMethod -Uri $Lookup -Headers $RESTHeaders -Method Get -ErrorAction Stop
		}
		catch {
			OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
        	OutputLogData -category "ERROR" -message "Could not access URL $Lookup, exiting."
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully accessed URL $Lookup, searching for link with rel $Rel and type $Type ..."
		
		#walk thru the Link items until we find our Rel type and Content type
		ForEach ($Link in $myvarRESTResponse.$Object.Link) {
			if (($Link.rel -eq $Rel) -and ($Link.type -eq $Type)) {
				$myvarRESTPOSTUrl = $Link.Href
				OutputLogData -category "INFO" -message "Found $myvarRESTPOSTUrl with rel $Rel and type $Type"
				break
			}#end if match rel and type
		}#end foreach link
		if (!$myvarRESTPOSTUrl) {
			OutputLogData -category "ERROR" -message "Could not find a URL that matches $Rel and $Type at $Lookup! Exiting."
			Remove-Variable -ErrorAction SilentlyContinue
			Exit
		}
	}#end process
	end {
		Remove-Variable Lookup
		Remove-Variable Rel
		Remove-Variable Type
		Remove-Variable SessionId
		Remove-Variable RESTHeaders
		Remove-Variable Object
		#return the URL
		return $myvarRESTPOSTUrl
	}#end
}#end function

#connect to a vCD server
function connectVcd {
	#input: vcd, credentials
	#output: connection information
<#
.SYNOPSIS
  Connect to a vCD instance using Connect-CiServer with error checking and handling.
.DESCRIPTION
  Connect to a vCD instance using Connect-CiServer with error checking and handling.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER vcd
  This the FQDN or IP of the vCD server you are trying to connect to.
.PARAMETER credentials
  This is a system crdentials object obtained with Get-Credentials.
.EXAMPLE
  connectVcd -Credentials (get-credentials) -Vcd vcloud.local
#>
	[CmdletBinding()]
	#region Param
	param
	(
		[string] $Vcd,
		[System.Management.Automation.PSCredential] $Credentials
	)
	#endregion
	
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

#get an OrgVdc object XML description
function getVcdOrgVdc {
	#input: org, orgVdcName, vcdConnect
	#output: OrgVdc XML description
<#
.SYNOPSIS
  Get the XML description of a given OrgVdc object.
.DESCRIPTION
  Get the XML description of a given OrgVdc object. The object is searched with Get-OrgVdc, then accessed thru its Url using REST.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER orgVdcName
  String containing the OrgVdc name as displayed in vCD.
.PARAMETER vcdConnect
  A connection object obtained from Connect-CiServer.
.EXAMPLE
  getVcdOrgVdc -orgVdcName AcmeOrg_Vdc -vcdConnect (Connect-CiServer -Server vcloud.local)
#>
	[CmdletBinding()]
	#region param
	param
	(
        [string] $org,
		[string] $orgVdcName,
		$vcdConnect
	)
	#endregion
	
    begin {
	}#end begin
	process {
		$myvarOrgVdc = Get-Org -Server $vcdConnect.Name -Name $org | Get-OrgVdc -Server $vcdConnect.Name -Name $orgVdcName #using get-orgvdc as search-cloud does not correctly return OrgVdcs...
		OutputLogData -category "INFO" -message "Processing $($myvarOrgVdc.Name)..."
		
		$myvarUrl = $myvarOrgVdc.Href #this is the Url we'll use to retrieve the XML description
		#preparing REST request headers
		$myvarHeaders = @{"Accept"="application/*+xml;version=5.1"}
		$myvarHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId}
		#retrieveing the XML description for that OrgVdc
		$myvarOrgVdcResponse = Invoke-RestMethod -Uri $myvarUrl -Headers $myvarHeaders -Method Get
	}#end process
	end {
		return $myvarOrgVdcResponse
	}#end
}#end function

#get an OrgVdcNetwork object XML description
function getVcdOrgVdcNetwork {
	#input: orgVdcNetworkName, vcdConnect
	#output: OrgVdcNetwork XML description
<#
.SYNOPSIS
  Get the XML description of a given OrgVdcNetwork object.
.DESCRIPTION
  Get the XML description of a given OrgVdcNetwork object. The object is searched with Get-OrgVdcNetwork, then accessed thru its Url using REST.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER orgVdcNetworkName
  String containing the OrgVdcNetwork name as displayed in vCD.
.PARAMETER vcdConnect
  A connection object obtained from Connect-CiServer.
.EXAMPLE
  getVcdOrgVdcNetwork -orgVdcNetworkName AcmeOrg_VdcNetwork1 -vcdConnect (Connect-CiServer -Server vcloud.local)
#>
	[CmdletBinding()]
	#region param
	param
	(
		[string] $orgName,
        [string] $orgVdcName,
        [string] $orgVdcNetworkName,
		$vcdConnect
	)
	#endregion
	
    begin {
	}#end begin
	process {
		$myvarOrgVdcNetwork = Get-Org -Server $vcdConnect.Name -Name $orgName | Get-OrgVdc -Server $vcdConnect.Name -Name $orgVdcName | Get-OrgVdcNetwork -Server $vcdConnect.Name -Name $orgVdcNetworkName #search-cloud does not accurately return OrgVdcNetwork objects, so using get-orgvdcnetwork instead
		OutputLogData -category "INFO" -message "Processing OrgVdcNetwork $($myvarOrgVdcNetwork.Name)..."
		$myvarUrl = $myvarOrgVdcNetwork.Href #this is the Url for that OrgVdcNetwork object which we'll use in our REST request
		#preparing REST headers
		$myvarHeaders = @{"Accept"="application/*+xml;version=5.5"}
		$myvarHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId}
		#using REST to retrieve the XML description for that object
		$myvarOrgVdcNetworkResponse = Invoke-RestMethod -Uri $myvarUrl -Headers $myvarHeaders -Method Get
	}#end process
	end {
		return $myvarOrgVdcNetworkResponse
	}#end
}#end function

#get any other type of vCloud Director object XML description
function getVcdObject {
	#input: type, name, vcd, href
	#output: vCD object XML description
<#
.SYNOPSIS
  Get the XML description of a given vCloud Director object.
.DESCRIPTION
  Get the XML description of a given vCloud Director object. The object is searched with Search-Cloud, then accessed using REST to obtain an XML description.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER type
  This the type of the object you want to get an XML for.  Any type that works with Search-Cloud is valid here.
.PARAMETER name
  This is the name of the object as displayed in vCD.
.PARAMETER vcdConnect
  This is the connnection information to vCD as obtained from a Connect-CiServer command.
.PARAMETER href
  This is the href of the object you want to lookup. If you specify an href, you do not need to specify a name and type, but you do need to specify an href type.
.PARAMETER hrefType
  This is the type of the object you want to lookup in REST API format such as "application/vnd.vmware.admin.user+xml".
.EXAMPLE
  getVcdObject -name AcmeOrg_EGW -type EdgeGateway -vcdConnect (Connect-CiServer -Server vcloud.acme.com)
#>
	[CmdletBinding()]
	#region param
	param
	(
		[string] $type,
		[string] $name,
		$vcdConnect,
		[string] $href,
		[string] $hreftype
	)
	#endregion
	
    begin {
	}#end begin
	process {
		if (!$href) {#do we have an href?
			#Search object
			try {
				$myvarObject = Search-Cloud -Server $vcdConnect.Name -QueryType $type -Name $name -ErrorAction Stop
			}
			catch {
				[System.Windows.Forms.MessageBox]::Show("Exception: " + $_.Exception.Message + " - Failed item:" + $_.Exception.ItemName ,"Error.",0,[System.Windows.Forms.MessageBoxIcon]::Exclamation)
				OutputLogData -category "ERROR" -message "$type with name $name not found"
				return $false
			}
			finally {
				$myvarObjectView = $myvarObject | Get-CIView
				$href = $myvarObjectView.href
				$hreftype = $myvarObjectView.Type
			}
		}#endif href
		
		if ($href) {
			#Getting the XML description using REST
            if ($type -and $name) {OutputLogData -category "INFO" -message "Setting up connection to REST API for $type $name..."}
            else {OutputLogData -category "INFO" -message "Setting up connection to REST API $href..."}
			
			$myvarWebclient = New-Object system.net.webclient
			$myvarWebclient.Headers.Add("x-vcloud-authorization",$vcdConnect.SessionId)
			$myvarwebclient.Headers.Add("accept",$hrefType + ";version=5.1")
            
            if ($type -and $name) {OutputLogData -category "INFO" -message "Retrieving details for $type $name..."}
            else {OutputLogData -category "INFO" -message "Retrieving $href details..."}

			[XML]$myvarObjectXML = $myvarwebclient.DownloadString($href)
		}#endif href
		else {
			OutputLogData -category "WARNING" -message "$type with name $name not found"
		}#endelse href
	}#end process
	end {
		return $myvarObjectXML
	}#end
}#end function

#function create a vCD organization object from an XML description
function createVcdOrg {
	#input: OrgXML, vcdConnect
	#output: REST response for object creation
<#
.SYNOPSIS
  Create a vCloud Director organization object from an XML description.
.DESCRIPTION
  Create a vCloud Director organization object from an XML description. This does not include any child objects.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER OrgXML
  This the XML description of the Organization object to create.
.PARAMETER vcdConnect
  This is the connection information for the vCD instance where you want to create the object. This is obtained from a Connect-CiServer.
.EXAMPLE
  createVcdOrg -OrgXML $AcmeOrgXmlObject -vcdConnect (Connect-CiServer -Server vcloud.acme.com) 
#>
	[CmdletBinding()]
	#region param
	param
	(
		[Xml] $OrgXML,
		$vcdConnect
	)
	#endregion
	
    begin {
	}#end begin
	process {
		#update the organization name if nessecary
		if ($rename) {
			$OrgXML.AdminOrg.name = $myvarNewOrgName
		}#endif rename
	
		#ok, we're ready to create the organization using the REST API, let's prepare headers and the XML body
		$myvarRESTContentType = "application/vnd.vmware.admin.organization+xml"
		$myvarRESTXMLBody = '<?xml version="1.0" encoding="UTF-8"?>' + $nl
		$myvarRESTXMLBody += $OrgXML.AdminOrg.OuterXml | Format-Xml #that takes care of the XML body
		$myvarRESTHeaders = @{"Accept"="application/*+xml;version=20.0"}
		$myvarRESTHeaders += @{"Content-Type"=$myvarRESTContentType}
		$myvarRESTHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId} #that takes care of the headers
		#we've got the content properly formatted, let's prepare the URL
		$myvarRESTUrl = getRESTUrl -lookup $($vcdConnect.HRef + "admin") -type $myvarRESTContentType -rel "add" -sessionId $vcdConnect.SessionId -Object VCloud
		
		#ok, we're ready to roll with the REST request
		OutputLogData -category "INFO" -message "Creating the organization..."
		try {
			$myvarRESTResponse = Invoke-RestMethod -Uri $myvarRESTUrl -Headers $myvarRESTHeaders -Method Post -Body $myvarRESTXMLBody -ErrorAction Stop
		}
		catch {
			OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
        	OutputLogData -category "ERROR" -message "Could not create the organization, exiting."
			$myvarRESTFullError = RESTFailureHandling
			if ($myvarRESTFullError -match '(?<= ] )(.+)(?=" minorErrorCode)') {
				$myError = $matches[0]
				OutputLogData -category "ERROR" -message "$myError"
			} else {OutputLogData -category "ERROR" -message "$myvarRESTFullError"}
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully created the organization."
	}#end process
	end {
	}#end
}#end function

#function create a user object in a vCD organization
function createVcdUser {
	#input: orgName, vcdConnect, userXML
	#output: REST response for object creation
<#
.SYNOPSIS
  Create a vCloud Director user object from an XML description.
.DESCRIPTION
  Create a vCloud Director user object from an XML description. This does not include any child or dependent objects.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER orgName
  This the name of the Organization you want the user to belong to.
.PARAMETER userXML
  This the XML description of the user object to create.
.PARAMETER vcdConnect
  This is the connection information for the vCD instance where you want to create the object. This is obtained from a Connect-CiServer.
.EXAMPLE
  createVcdUser -orgName AcmeOrg -XMLObject $UserXmlObject -vcdConnect (Connect-CiServer -Server vcloud.acme.com)  
#>
	[CmdletBinding()]
	#region param
	param
	(
		[string] $OrgName,
		$vcdConnect,
		[Xml] $userXML
	)
	#endregion
	
    begin {
	}#end begin
	process {
	
		#region XML Editing
		#we need to know which organization this user belongs to
		if (!$OrgName) {$OrgName = Read-Host "Enter the name of the Organization where this user will be created"}#endif no org
		try {
		$myvarOrgView = Search-Cloud -Server $vcdConnect.Name -QueryType Organization -Name $OrgName -ErrorAction Stop | Get-CIView
		}
		catch {
			OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
        	OutputLogData -category "ERROR" -message "Could not find the Organization $OrgName, exiting."
			Exit
		}
		$myvarOrgURL = $myvarOrgView.Href
		
		#we need to update the Role href in the XML description
		$myvarRoleView = Search-Cloud -Server $vcdConnect.Name -QueryType Role -Name $userXML.User.Role.name -ErrorAction Stop | Get-CIView
		$myvarRoleUrl = $myvarRoleView.Href
		$userXML.User.Role.href = $myvarRoleUrl
		
		#finally, we need to prompt for the password and add it to the XML description
		if (!$userPassword) {
			$myvarPasswordSecureString = Read-Host "Please enter the desired password for user $($userXML.User.Name)" -AsSecureString
			$myvarPassword = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($myvarPasswordSecureString) #decoding password as REST API wants unsecure string, phase 1/2
			$myvarPasswordString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($myvarPassword) #decoding password as REST API wants unsecure string, phase 2/2
		}#endif userPassword
		else {
			$myvarPasswordString = $userPassword
		}#endelse userPassword
		($myvarXMLElement = $userXML.CreateElement("Password",$userXML.User.xmlns)) | Out-Null #let's create a new password element in the XML description in the same namespace as User
		($userXML.User.InsertAfter($myvarXMLElement,$userXML.User.Role)) | Out-Null #we now insert the new element after the Role element
		($userXML.User.Password = $myvarPasswordString) | Out-Null #and write the unscrambled password in it
		Remove-Variable myvarPasswordString #we immediately remove the unscrambled password from memory for security's sake
		Remove-Variable myvarPassword
		
		#endregion
	
		#region REST POST
		#ok, we're ready to create the organization using the REST API, let's prepare headers and the XML body
		$myvarRESTContentType = "application/vnd.vmware.admin.user+xml"
		$myvarRESTXMLBody = '<?xml version="1.0" encoding="UTF-8"?>' + $nl
		$myvarRESTXMLBody += $userXML.User.OuterXml | Format-Xml #that takes care of the XML body
		$myvarRESTHeaders = @{"Accept"="application/*+xml;version=20.0"}
		$myvarRESTHeaders += @{"Content-Type"=$myvarRESTContentType}
		$myvarRESTHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId} #that takes care of the headers
		#we've got the content properly formatted, let's prepare the URL
		$myvarRESTUrl = getRESTUrl -lookup $myvarOrgUrl -type $myvarRESTContentType -rel "add" -sessionId $vcdConnect.SessionId -Object AdminOrg
		
		#ok, we're ready to roll with the REST request
		OutputLogData -category "INFO" -message "Creating the user $($userXML.User.Name)..."
		try {
			$myvarRESTResponse = Invoke-RestMethod -Uri $myvarRESTUrl -Headers $myvarRESTHeaders -Method Post -Body $myvarRESTXMLBody -ErrorAction Stop
		}
		catch {
			OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
        	OutputLogData -category "ERROR" -message "Could not create the user $($userXML.User.Name), exiting."
			$myvarRESTFullError = RESTFailureHandling
			if ($myvarRESTFullError -match '(?<= ] )(.+)(?=" minorErrorCode)') {
				$myError = $matches[0]
				OutputLogData -category "ERROR" -message "$myError"
			} else {OutputLogData -category "ERROR" -message "$myvarRESTFullError"}
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully created the user $($userXML.User.Name)."
		#endregion
	}#end process
	end {
	}#end
}#end function

#function create a role object
function createVcdRole {
	#input: vcdConnect, roleXML
	#output: REST response for object creation
<#
.SYNOPSIS
  Create a vCloud Director role object from an XML description.
.DESCRIPTION
  Create a vCloud Director role object from an XML description.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER roleXML
  This the XML description of the role object to create.
.PARAMETER vcdConnect
  This is the connection information for the vCD instance where you want to create the object. This is obtained from a Connect-CiServer.
.EXAMPLE
  createVcdRole -roleXML $RoleXmlObject -vcdConnect (Connect-CiServer -Server vcloud.acme.com)
#>
	[CmdletBinding()]
	#region param
	param
	(
		$vcdConnect,
		[Xml] $roleXML
	)
	#endregion
	
    begin {
		
	}#end begin
	process {
		#region XML Editing
		#we need to know which organization this user belongs to
		if (!$OrgName) {$OrgName = Read-Host "Enter the name of the Organization where this user will be created"}#endif no org
		try {
		$myvarOrgView = Search-Cloud -Server $vcdConnect.Name -QueryType Organization -Name $OrgName -ErrorAction Stop | Get-CIView
		}
		catch {
			OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
        	OutputLogData -category "ERROR" -message "Could not find the Organization $OrgName, exiting."
			Exit
		}
		$myvarOrgURL = $myvarOrgView.Href
		
		#we need to update the Role href in the XML description
		$myvarRoleView = Search-Cloud -Server $vcdConnect.Name -QueryType Role -Name $roleXML.User.Role.name -ErrorAction Stop | Get-CIView
		$myvarRoleUrl = $myvarRoleView.Href
		$roleXML.User.Role.href = $myvarRoleUrl
		
		#finally, we need to prompt for the password and add it to the XML description
		if (!$userPassword) {
			$myvarPasswordSecureString = Read-Host "Please enter the desired password for user $($XMLObject.User.Name)" -AsSecureString
			$myvarPassword = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($myvarPasswordSecureString) #decoding password as REST API wants unsecure string, phase 1/2
			$myvarPasswordString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($myvarPassword) #decoding password as REST API wants unsecure string, phase 2/2
		}#endif userPassword
		else {
			$myvarPasswordString = $userPassword
		}#endelse userPassword
		($myvarXMLElement = $roleXML.CreateElement("Password",$roleXML.User.xmlns)) | Out-Null #let's create a new password element in the XML description in the same namespace as User
		($roleXML.User.InsertAfter($myvarXMLElement,$roleXML.User.Role)) | Out-Null #we now insert the new element after the Role element
		($roleXML.User.Password = $myvarPasswordString) | Out-Null #and write the unscrambled password in it
		Remove-Variable myvarPasswordString #we immediately remove the unscrambled password from memory for security's sake
		Remove-Variable myvarPassword
		
		#endregion
		
		#region REST POST
		#ok, we're ready to create the role using the REST API, let's prepare headers and the XML body
		$myvarRESTContentType = "application/vnd.vmware.admin.role+xml"
		$myvarRESTXMLBody = '<?xml version="1.0" encoding="UTF-8"?>' + $nl
		$myvarRESTXMLBody += $roleXML.Role.OuterXml | Format-Xml #that takes care of the XML body
		$myvarRESTHeaders = @{"Accept"="application/*+xml;version=20.0"}
		$myvarRESTHeaders += @{"Content-Type"=$myvarRESTContentType}
		$myvarRESTHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId} #that takes care of the headers
		#we've got the content properly formatted, let's prepare the URL
		$myvarRESTUrl = $vcdConnect.ServiceUri.AbsoluteUri + "admin/roles"
		
		#ok, we're ready to roll with the REST request
		OutputLogData -category "INFO" -message "Creating the role $($roleXML.Role.Name)..."
		try {
			$myvarRESTResponse = Invoke-RestMethod -Uri $myvarRESTUrl -Headers $myvarRESTHeaders -Method Post -Body $myvarRESTXMLBody -ErrorAction Stop
		}
		catch {
			OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
        	OutputLogData -category "ERROR" -message "Could not create the role $($roleXML.Role.Name), exiting."
			$myvarRESTFullError = RESTFailureHandling
			if ($myvarRESTFullError -match '(?<= ] )(.+)(?=" minorErrorCode)') {
				$myError = $matches[0]
				OutputLogData -category "ERROR" -message "$myError"
			} else {OutputLogData -category "ERROR" -message "$myvarRESTFullError"}
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully created the role $($roleXML.Role.Name)."
		#endregion
	}#end process
	end {
	}#end
}#end function

#function create an OrgVdc object
function createVcdOrgVdc {
	#input: orgName, vcd, OrgVdcXML
	#output: REST response for object creation
<#
.SYNOPSIS
  Create a vCloud Director organization virtual datacenter object from an XML description.
.DESCRIPTION
  Create a vCloud Director organization virtual datacenter object from an XML description. This does not include any child objects.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER orgName
  This the name of the Organizationwhere you want the OrgVdc object to be created.
.PARAMETER OrgVdcXML
  This the XML description of the Organization virtual datacenter object to create.
.PARAMETER vcdConnect
  This is the connection information for the vCD instance where you want to create the object. This is obtained from a Connect-CiServer.
.EXAMPLE
  createVcdOrgVdc -orgName AcmeOrg -OrgVdcXML $AcmeOrgVdcXmlObject -vcdConnect (Connect-CiServer -Server vcloud.acme.com)
#>
	[CmdletBinding()]
	#region param
	param
	(
		[string] $orgName,
		[string] $vcd,
		[Xml] $OrgVdcXML
	)
	#endregion
	
    begin {
	}#end begin
	process {
		#region XMLEditing
		#OrgVdc are created in an organization and with a Provider vDC, so let's prompt the user for the org name
		if (!$orgName) {$orgName = Read-Host "Please enter the name of the Organization where you want to migrate this OrgVdc"}
		$myvarProvDC = Search-Cloud -Server $vcd -QueryType ProviderVdc
		if ($myvarProvDC.Count -ne 1) { #is there more than 1 provider vdc defined?
			if ($pvDC) {$myvarProvDCName = $pvDC} else {$myvarProvDCName = Read-Host "Please enter the name of the ProviderVdc for this OrgVdc"}
			#Let's get the Provider vDC reference
			OutputLogData -category "INFO" -message "Searching for Provider vDC $myvarProvDCName..."
            $myvarProvDC = Search-Cloud -Server $vcd -QueryType ProviderVdc -Name $myvarProvDCName -ErrorAction Stop
			$myvarProvDCView = $myvarProvDC | Get-CIView
			if (!$myvarProvDCView) {
				Write-Warning $($_.Exception.Message)
	        	OutputLogData -category "ERROR" -message "Could not find Provider vDC $myvarProvDCName, exiting."
				Exit
			}#end if not ProvDC
			OutputLogData -category "INFO" -message "Found $myvarProvDCName."
		}#end if not single provider vdc 
		else {
			$myvarProvDCView = Search-Cloud -Server $vcd -QueryType ProviderVdc | Get-CIView
		}#endelse not single provider vdc
		
		#Now we search for that Org URL on the target
		OutputLogData -category "INFO" -message "Searching for organization $orgName..."
		$myvarOrgView = Search-Cloud -Server $vcd -QueryType Organization -Name $orgName -ErrorAction Stop | Get-CIView
		if (!$myvarOrgView) {
			Write-Warning $($_.Exception.Message)
        	OutputLogData -category "ERROR" -message "Could not find Organization $orgName, exiting."
			Exit
		}#end if not Org
		OutputLogData -category "INFO" -message "Found $orgName."
		
		$myvarOrgURL = $myvarOrgView.Href
		$myvarProvDCURL = $myvarProvDCView.Href
	
		#endregion
		

		#region XML to VimAutomation.Cloud.Views.AdminVdc translation	
		#there seems to be a bug in vCD 8.10 REST API for OrgVdc creation, so instead we are going to translate the XML into native PowerCLI object
		$myvarAdminVdcObject = New-Object VMware.VimAutomation.Cloud.Views.AdminVdc
		
        #the two items below are customizable using the static variables in the variables region of the script
		if ($ResourceGuaranteedMemory -eq "source") {$myvarAdminVdcObject.ResourceGuaranteedMemory = $orgVdcXML.AdminVdc.ResourceGuaranteedMemory} else {$myvarAdminVdcObject.ResourceGuaranteedMemory = $ResourceGuaranteedMemory}
		if ($ResourceGuaranteedCpu -eq "source") {$myvarAdminVdcObject.ResourceGuaranteedCpu = $orgVdcXML.AdminVdc.ResourceGuaranteedCpu} else {$myvarAdminVdcObject.ResourceGuaranteedCpu = $ResourceGuaranteedCpu}
		
        $myvarAdminVdcObject.VCpuInMhz = $orgVdcXML.AdminVdc.VCpuInMhz
		$myvarAdminVdcObject.IsThinProvision = $orgVdcXML.AdminVdc.IsThinProvision
		$myvarAdminVdcObject.UsesFastProvisioning = $orgVdcXML.AdminVdc.UsesFastProvisioning
		$myvarAdminVdcObject.AllocationModel = $orgVdcXML.AdminVdc.AllocationModel
		
		$myvarAdminVdcObject.StorageCapacity = New-Object VMware.VimAutomation.Cloud.Views.CapacityWithUsage 
        $myvarAdminVdcObject.StorageCapacity.Units = "MB" 
        $myvarAdminVdcObject.StorageCapacity.Limit = 0
		
		$myvarAdminVdcObject.ComputeCapacity = New-Object VMware.VimAutomation.Cloud.Views.ComputeCapacity 
        $myvarAdminVdcObject.ComputeCapacity.Cpu = New-Object VMware.VimAutomation.Cloud.Views.CapacityWithUsage 
        $myvarAdminVdcObject.ComputeCapacity.Cpu.Units = "MHz" 
        $myvarAdminVdcObject.ComputeCapacity.Cpu.Limit = $orgVdcXML.AdminVdc.ComputeCapacity.Cpu.Limit 
        $myvarAdminVdcObject.ComputeCapacity.Cpu.Allocated = $orgVdcXML.AdminVdc.ComputeCapacity.Cpu.Allocated
		$myvarAdminVdcObject.ComputeCapacity.Memory = New-Object VMware.VimAutomation.Cloud.Views.CapacityWithUsage 
        $myvarAdminVdcObject.ComputeCapacity.Memory.Units = "MB" 
        $myvarAdminVdcObject.ComputeCapacity.Memory.Limit = $orgVdcXML.AdminVdc.ComputeCapacity.Memory.Limit
        $myvarAdminVdcObject.ComputeCapacity.Memory.Allocated = $orgVdcXML.AdminVdc.ComputeCapacity.Memory.Allocated 
				
		$myvarAdminVdcObject.NicQuota = $orgVdcXML.AdminVdc.NicQuota
		$myvarAdminVdcObject.NetworkQuota = $orgVdcXML.AdminVdc.NetworkQuota
		$myvarAdminVdcObject.UsedNetworkCount = $orgVdcXML.AdminVdc.UsedNetworkCount
		$myvarAdminVdcObject.VmQuota = $orgVdcXML.AdminVdc.VmQuota
		$myvarAdminVdcObject.IsEnabled = $orgVdcXML.AdminVdc.IsEnabled
		
		$myvarAdminVdcObject.VdcStorageProfiles = New-Object VMware.VimAutomation.Cloud.Views.VdcStorageProfiles
		$myvarAdminVdcObject.VdcStorageProfiles.VdcStorageProfile[0] = New-Object VMware.VimAutomation.Cloud.Views.VdcStorageProfiles.Reference
		
		$myvarAdminVdcObject.Name = $myvarNewOrgVdcName
		$myvarAdminVdcObject.Description = $orgVdcXML.AdminVdc.Description
		
		#$myvarAdminVdcObject.ResourceEntities
		#$myvarAdminVdcObject.AvailableNetworks
		#$myvarAdminVdcObject.Tasks
		#$myvarAdminVdcObject.Id
		#$myvarAdminVdcObject.OperationKey
		#$myvarAdminVdcObject.Client
		#$myvarAdminVdcObject.Href
		#$myvarAdminVdcObject.Type
		#$myvarAdminVdcObject.Link
		#$myvarAdminVdcObject.AnyAttr
		#$myvarAdminVdcObject.VCloudExtension
		#$myvarAdminVdcObject.VendorServices
		#$myvarAdminVdcObject.OverCommitAllowed
		#$myvarAdminVdcObject.Status
		#$myvarAdminVdcObject.Capabilities
		
		
        
		$myvarProviderVdc = Get-ProviderVdc -Server $vcd -Name $myvarProvDCView.Name 
        $myvarProviderVdcRef = New-Object VMware.VimAutomation.Cloud.Views.Reference 
        $myvarProviderVdcRef.Href = $myvarProviderVdc.Href
        $myvarAdminVdcObject.ProviderVdcReference =$myvarProviderVdcRef
        
		####Add support for multiple network pools here
		$myvarNetworkPool = Get-NetworkPool -Server $vcd -ProviderVdc $myvarProvDCView.Name
		if ($myvarNetworkPool.Count -gt 1) { #we have more than one network pool
			#OutputLogData -category "ERROR" -message "There is more than one Network Pool which this script does not deal with: exiting"
			#Exit
			$myvarNetworkPoolName = Read-Host "Please enter the name of the network pool for this OrgVdc"
			$myvarNetworkPool = Get-NetworkPool -Server $vcd -Name $myvarNetworkPoolName
		}
		$myvarNetworkPoolRef = New-Object VMware.VimAutomation.Cloud.Views.Reference
		$myvarNetworkPoolRef.Href = $myvarNetworkPool.Href
		$myvarAdminVdcObject.NetworkPoolReference = $myvarNetworkPoolRef
		
        $myvarOrgED = (Get-Org -Server $vcd -Name $orgName).ExtensionData 
		
		OutputLogData -category "INFO" -message "Creating the OrgVdc $myvarNewOrgVdcName for $orgName..."
		try
		{
			$myvarOrgED.CreateVdc($myvarAdminVdcObject) | Out-Null
		}
		catch
		{
			OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
        	OutputLogData -category "ERROR" -message "Could not create the OrgVdc $myvarNewOrgVdcName for $orgName : exiting."
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully created the OrgVdc $myvarNewOrgVdcName for $orgName."
		
        #endregion


        #region Dealing with storage profiles

        # Find the Storage Profiles in the Provider vDC to be added to the Org vDC
        OutputLogData -category "INFO" -message "Waiting for 20 seconds before configuring storage policies..."
        Start-Sleep -Seconds 20
        OutputLogData -category "INFO" -message "Getting Storage Profiles from Provider vDC..."
        try {
            $pvDCProfiles = search-cloud -Server $vcd -QueryType ProviderVdcStorageProfile -ErrorAction Stop | where {$_.ProviderVdc -eq $myvarProvDC.Id} | Get-CIView
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Exception: " + $_.Exception.Message + " - Failed item:" + $_.Exception.ItemName ,"Error.",0,[System.Windows.Forms.MessageBoxIcon]::Exclamation)
			OutputLogData -category "ERROR" -message "Could not retrieve ProviderVdcStorageProfile from $vcd."
			return $false
        }
        
        OutputLogData -category "INFO" -message "Retrieving the newly created OrgVdc object from the target..."
        $myvarOrgVdcObject = Get-Org -Server $vcd -Name $orgname | Get-OrgVdc -Server $vcd -Name $myvarNewOrgVdcName

        if ($pvDCProfiles) {
            # Strip out any disabled Profiles
            OutputLogData -category "INFO" -message "Stripping out disabled Profiles..."
            $pvDCProfiles = $pvDCProfiles | where {$_.Enabled -eq $True}

            # Strip out the generic * Profile
            OutputLogData -category "INFO" -message "Removing the * (Any) Profile from the list of source storage capabilities..."
            $pvDCProfiles = $pvDCProfiles | where {$_.Name -ne "*"}

            # Loop through the collected profiles and assign them to the new Org VDC
            OutputLogData -category "INFO" -message "Writing Storage Profiles to Organization vDC..."

            foreach ($storProfile in $pvDCProfiles) {

                # Create a new object of type VdcStorageProfileParams and fill in the parameters for the new Org vDC passing in the href of the Provider vDC Storage Profile
                $spParams = new-object VMware.VimAutomation.Cloud.Views.VdcStorageProfileParams 
                $spParams.Limit = 1024000 
                $spParams.Units = "MB" 
                $spParams.ProviderVdcStorageProfile = $storProfile.href
                $spParams.Enabled = $true
                $spParams.Default = $false 

                # Create an UpdateVdcStorageProfiles object and put the new parameters into the AddStorageProfile element
                $UpdateParams = new-object VMware.VimAutomation.Cloud.Views.UpdateVdcStorageProfiles 
                $UpdateParams.AddStorageProfile = $spParams

                # Create the new Storage Profile entry in my test Org vDC
                $myvarOrgVdcObject.ExtensionData.CreateVdcStorageProfile($UpdateParams) | Out-Null
                $myvarOrgVdcObject.ExtensionData.UpdateServerData()
                OutputLogData -category "INFO" -message "Added storage profile $($storProfile.Name)."
                Start-Sleep -Seconds 5

            }#end foreach storage profile


            # Prompt user to select the default storage profile to use.  
            #OutputLogData -category "INFO" -message "Select the Storage Profile you want to use for the DEFAULT for this OrgVDC"
            if ($pvdcProfiles.Count -gt 1) {
                $DefaultProfile = Read-Host "Enter the name of the default storage profile you want to use"
            }
            else {
                $DefaultProfile = $pvdcProfiles.Name
            }

            $orgvDCDefaultProfile = search-cloud -server $vcd -querytype AdminOrgVdcStorageProfile | where {($_.Name -match $($DefaultProfile)) -and ($_.VdcName -eq $myvarNewOrgVdcName)} | Get-CIView

            # Set the Profile as the new default
            OutputLogData -category "INFO" -message "Setting Default Storage Profile to $DefaultProfile..."  
            $orgvDCDefaultProfile.Default = $true  
            $orgvDCDefaultProfile.UpdateServerData() | Out-Null

            # Get object representing the * (Any) Profile in the Org vDC  
            $orgvDCAnyProfile = search-cloud -server $vcd -querytype AdminOrgVdcStorageProfile | where {($_.Name -match '\*') -and ($_.VdcName -eq $myvarNewOrgVdcName)} | Get-CIView  

            # Disable the "* (any)" Profile
            OutputLogData -category "INFO" -message "Removing the (*) Any Profile from this OrgVdc..."  
            $orgvDCAnyProfile.Enabled = $False  
            $orgvDCAnyProfile.UpdateServerData() | Out-Null

            # Remove the "* (any)" profile form the Org vDC completely  
            $ProfileUpdateParams = new-object VMware.VimAutomation.Cloud.Views.UpdateVdcStorageProfiles  
            $ProfileUpdateParams.RemoveStorageProfile = $orgvDCAnyProfile.href  
            $myvarOrgVdcObject.extensiondata.CreatevDCStorageProfile($ProfileUpdateParams) | Out-Null
            $myvarOrgVdcObject.ExtensionData.UpdateServerData()
        }#endif pvDCStorageProfiles
        else {
            OutputLogData -category "WARNING" -message "There was no storage profiles to process!"
        }#endelse pvDCStorageProfiles

        OutputLogData -category "INFO" -message "Setting Thin Provisioning Option..."
        $myvarOrgVdcObject | Set-OrgVdc -UseFastProvisioning $false -ThinProvisioned $true | Out-Null

        #endregion

	}#end process
	end {
	}#end
}#end function

#function create an EdgeGateway object
function createVcdEdgeGateway {
	#input: orgVdcName, vcdConnect, EdgeGatewayXML
	#output: REST response for object creation
<#
.SYNOPSIS
  Create a vCloud Director EdgeGateway object from an XML description.
.DESCRIPTION
  Create a vCloud Director EdgeGateway object from an XML description. Note that internal gateway interfaces, disabled services and dhcp services are removed as they are dependent on OrgVdcNetwork objects which may not exist.  When all objects exist, use the setVcdEdgeGatewayServiceConfiguration function to preserve all settings (except for disabled services as those result in a REST API bad request error).
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER EdgeGatewayXML
  This the XML description of the EdgeGateway object to create.
.PARAMETER vcdConnect
  This is the connection information for the vCD instance where you want to create the object. This is obtained from a Connect-CiServer.
.EXAMPLE
  createVcdEdgeGateway -EdgeGatewayXML $EdgeGatewayXmlObject -vcdConnect (Connect-CiServer -Server vcloud.acme.com)
#>
	[CmdletBinding()]
	#region param
	param
	(
		[string] $orgVdcName,
		$vcdConnect,
		[Xml] $EdgeGatewayXML
	)
	#endregion
	
    begin {
	}#end begin
	process {
		
		#region XML Editing
		
		if (!$orgVdcName) {#An EdgeGateway is created in an OrgVdc, so let's prompt which OrgVdc to target
			OutputLogData -category "WARNING" -message "You are trying to migrate an EdgeGateway, which requires an OrgVdc"
			$orgVdcName = Read-Host "Enter the OrgVdc name for this edge gateway"
		}
		#Let's get the URL for this OrgVdc
		$myvarOrgVdc = Get-OrgVdc -Server $vcdConnect.Name -Name $orgVdcName
		$myvarOrgVdcUrl = $myvarOrgVdc.Href
		
		if ($rename) {
			$EdgeGatewayXML.EdgeGateway.name = $myvarNewEdgeGatewayName
		}#endif rename
		
		OutputLogData -category "INFO" -message "Processing EdgeGateway $($EdgeGatewayXML.EdgeGateway.name)..."
		
		OutputLogData -category "INFO" -message "Switching off UseDefaultRouteForDnsRelay..."
		$EdgeGatewayXML.EdgeGateway.Configuration.UseDefaultRouteForDnsRelay = "false" #turn off default route
		
		#making sure the description is not an invalid string...
		$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description) -replace "`n",',' #replacing line returns with commas
		$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description) -replace "&",''   #removing ampersand characters
		$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description) -replace "<",''   #removing < characters
		$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description) -replace ">",''   #removing > characters
		if (($EdgeGatewayXML.EdgeGateway.Description).Length -gt 128) {$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description).substring(0,128)} #trimming the description string to 128 characters which is the max allowed in vCD 8.10 API
		
		#region Internal Gateway Interfaces
		#we now need to remove all internal gateway interfaces which will reference Org vCD Networks which don't exist yet, then turn off default route or the REST API won't take it. This will have have to be re-enabled manually after the object has been created.
		OutputLogData -category "INFO" -message "Removing internal interfaces from XML description..."
		foreach ($myvarGatewayInterface in $EdgeGatewayXML.EdgeGateway.Configuration.GatewayInterfaces.GatewayInterface) { #list all gateway interfaces in the xml
			if ($myvarGatewayInterface.InterfaceType -eq "internal") { #check if this is an internal interface
				$EdgeGatewayXML.EdgeGateway.Configuration.GatewayInterfaces.RemoveChild($myvarGatewayInterface) | Out-Null #remove the internal interface
			}#endif internal interface
			else { #this is not an internal interface, so we'll keep it
				OutputLogData -category "INFO" -message "Switching off UseForDefaultRoute on $($myvarGatewayInterface.name)..."
				$myvarGatewayInterface.UseForDefaultRoute = "false" #turn off default route
				$myvarNetworkView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarGatewayInterface.Network.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
				if ($myvarNetworkView) { #check that we have found the external network
					$myvarGatewayInterface.Network.href = $myvarNetworkView.Href #update the reference to the external network with the target vCD object Url
				}#endif network view exists
				else { #we haven't found the external network
					OutputLogData -category "ERROR" -message "Could not find the external network $($myvarGatewayInterface.Network.name) on the vCloud Director instance which is required by this EdgeGateway: exiting"
					Exit
				}#endelse network view exists
			}#end else internal interface
		}#end foreach gateway interface
		#endregion 
		
		#region DhcpServices
		#we need to remove GatewayDhcpServices as those reference routed OrgVdc networks which can't be created until the edge gateway is created...
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayDhcpService) {
			OutputLogData -category "INFO" -message "Removing DHCP services from XML description..."
			$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayDhcpService) | Out-Null
		}#endif dhcp service
		#endregion
		
		#region NAT rules
		#let's take care of gateway interfaces in nat rules
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.NatService) {
			OutputLogData -category "INFO" -message "Updating external network references in Nat rules..."
			foreach ($myvarNatRule in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.NatService.NatRule) {
				if (!($EdgeGatewayXML.EdgeGateway.Configuration.GatewayInterfaces.GatewayInterface | where {$_.name -eq $myvarNatRule.GatewayNatRule.Interface.name})) {#testing if the interface used in that NAT rule is an internal interface, in which case we must remove the NAT rule for now
					$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.NatService.RemoveChild($myvarNATRule) | Out-Null
				}#endif interface in nat rule is internal
				else {
					$myvarInterfaceView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarNatRule.GatewayNatRule.Interface.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
					if ($myvarInterfaceView) { #check that we have found the external network
						$myvarNatRule.GatewayNatRule.Interface.href = $myvarInterfaceView.Href #update the reference to the external network with the target vCD object Url
					}#endif network view exists
					else { #we haven't found the external network
						OutputLogData -category "ERROR" -message "Could not find the external network $($myvarNatRule.GatewayNatRule.Interface.name) on the vCloud Director instance which is required by this EdgeGateway: exiting"
						Exit
					}#endelse network view exists
				}#endelse interface in nat rule is internal
			}#end foreach natrule
		}#endif natservice
		#endregion
		
		#region Load Balancer
		#let's update interface references in virtual server objects in the LoadBalancer service configuration
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService) {
			foreach ($myvarVirtualServer in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService.VirtualServer) {
				$myvarInterfaceView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarVirtualServer.Interface.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
				if ($myvarInterfaceView) { #check that we have found the external network
					$myvarVirtualServer.Interface.href = $myvarInterfaceView.Href #update the reference to the external network with the target vCD object Url
				}#endif network view exists
				else { #we haven't found the external network
					OutputLogData -category "ERROR" -message "Could not find the external network $($myvarVirtualServer.Interface.name) on the target vDC which is required in this Load Balancer Virtual Server element: exiting"
					Exit
				}#endelse network view exists
			}#end foreach dhcp pool
		}#endif GatewayDhcpService
		#endregion
		
		#region Disabled Services
		#remove other services if they are not enabled
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayIpsecVpnService) {
			if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayIpsecVpnService.IsEnabled -eq "false") {
				$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayIpsecVpnService) | Out-Null
				OutputLogData -category "INFO" -message "Removed GatewayIpsecVpnService definition because it was disabled."
			}#endif disabled
		}#endif disabled vpn service
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService) {
			if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService.IsEnabled -eq "false") {
				$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService) | Out-Null
				OutputLogData -category "INFO" -message "Removed StaticRoutingService definition because it was disabled."
			}#endif disabled
		}#endif disabled static routing service
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService) {
			if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService.IsEnabled -eq "false") {
				$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService) | Out-Null
				OutputLogData -category "INFO" -message "Removed LoadBalancerService definition because it was disabled."
			}#endif disabled
		}#endif disabled load balancer service
		#endregion
		
		#region Static Routes
		#let's take care of GatewayInterface href in static routes
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService) {
			OutputLogData -category "INFO" -message "Updating external network references in StaticRoutingService definition..."
			foreach ($myvarStaticRoute in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService.StaticRoute) {
				$myvarInterfaceView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarStaticRoute.GatewayInterface.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
				if ($myvarInterfaceView) { #check that we have found the external network
					$myvarStaticRoute.GatewayInterface.href = $myvarInterfaceView.Href #update the reference to the external network with the target vCD object Url
				}#endif network view exists
				else { #we haven't found the external network
					OutputLogData -category "ERROR" -message "Could not find the external network $($myvarStaticRoute.GatewayNatRule.name) on the vCloud Director instance which is required by this EdgeGateway: exiting"
					Exit
				}#endelse network view exists
			}#end foreach static route
		}#endif StaticRoutingService
		#endregion
		
		#endregion
		
		#region REST POST
		#ok, we're ready to create the organization using the REST API, let's prepare headers and the XML body
		$myvarRESTContentType = "application/vnd.vmware.admin.edgeGateway+xml"
		$myvarRESTXMLBody = '<?xml version="1.0" encoding="UTF-8"?>' + $nl
		$myvarRESTXMLBody += $EdgeGatewayXML.EdgeGateway.OuterXml | Format-Xml #that takes care of the XML body
		
		#we've got the content properly formatted, let's prepare the URL
		$myvarRESTUrl = getRESTUrl -lookup $myvarOrgVdcUrl -type $myvarRESTContentType -rel "add" -sessionId $vcdConnect.SessionId -Object AdminVdc
		
		#let's get the headers ready
		$myvarRESTHeaders = @{"Accept"="application/*+xml;version=20.0"}
		$myvarRESTHeaders += @{"Content-Type"=$myvarRESTContentType}
		$myvarRESTHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId} #that takes care of the headers
		
		#ok, we're ready to roll with the REST request
		OutputLogData -category "INFO" -message "Creating the EdgeGateway $($EdgeGatewayXML.EdgeGateway.Name)..."
		try {
			$myvarRESTResponse = Invoke-RestMethod -Uri $myvarRESTUrl -Headers $myvarRESTHeaders -Method Post -Body $myvarRESTXMLBody -ErrorAction Stop
		}
		catch {
			OutputLogData -category "ERROR" -message "$($($_.Exception.Message))"
        	OutputLogData -category "ERROR" -message "Could not create the EdgeGateway $($EdgeGatewayXML.EdgeGateway.Name) : exiting."
			$myvarRESTFullError = RESTFailureHandling
			if ($myvarRESTFullError -match '(?<= ] )(.+)(?=" minorErrorCode)') {
				$myError = $matches[0]
				OutputLogData -category "ERROR" -message "$myError"
			} else {OutputLogData -category "ERROR" -message "$myvarRESTFullError"}
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully created the EdgeGateway $($EdgeGatewayXML.EdgeGateway.Name)."
		#endregion
	}#end process
	end {
	}#end
}#end function

#function apply EdgeGateway Service Configuration only
function setVcdEdgeGatewayServiceConfiguration {
	#input: EdgeGatewayXML, vcdConnect
	#output: REST response for service configuration
<#
.SYNOPSIS
  Configure the services on a vCloud Director EdgeGateway object from an XML description.
.DESCRIPTION
  Configure the services on a vCloud Director EdgeGateway object from an XML description. Note that this requires that all required OrgVdcNetwork exist. Disabled services are removed from the XML description as those result in a REST API bad request error).
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER EdgeGatewayXML
  This the XML description of the EdgeGateway object to configure.
.PARAMETER vcdConnect
  This is the connection information for the vCD instance where you want to create the object. This is obtained from a Connect-CiServer.
.EXAMPLE
  setVcdEdgeGatewayServiceConfiguration -xmlObject $EdgeGatewayXmlObject -vcdConnect (Connect-CiServer -Server vcloud.acme.com)
#>
	[CmdletBinding()]
	#region param
	param
	(
		[Xml]$EdgeGatewayXML,
		$vcdConnect
	)
	#endregion
	
    begin {
	}#end begin
	process {
		
		#region XML Editing
		if ($rename) {
			$EdgeGatewayXML.EdgeGateway.name = $myvarNewEdgeGatewayName
		}#endif rename
		
		#let's figure out which edge gateway we're working with here
		$myvarEdgeGatewayView = Search-Cloud -Server $vcdConnect.Name -QueryType EdgeGateway -Name $EdgeGatewayXML.EdgeGateway.name -ErrorAction Stop | Get-CIView
		if (!$myvarEdgeGatewayView) {
			OutputLogData -category "ERROR" -message "Could not find EdgeGateway with name $($EdgeGatewayXML.EdgeGateway.name) on vCloud Director server $($vcdConnect.Name): Exiting!"
			Remove-Variable * -ErrorAction SilentlyContinue
			Exit
		}#endif no Edge Gateway on target
		$myvarEdgeGatewayUrl = $myvarEdgeGatewayView.href
		
		#region DHCP Pools
		#let's update Network references for dhcp pool if GatewayDhcpService is part of the XML description
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayDhcpService) {
			foreach ($myvarPool in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayDhcpService.Pool) {
				$myvarPoolNetwork = Get-OrgVdcNetwork -Server $vcdConnect.Name -Name $myvarPool.Network.name #get the network href
				$myvarPool.Network.href = $myvarPoolNetwork.Href #update the href
			}#end foreach dhcp pool
		}#endif GatewayDhcpService
		#endregion
		
		#region NAT rules
		#let's take care of gateway interfaces in nat rules
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.NatService) {
			OutputLogData -category "INFO" -message "Updating external network references in Nat rules..."
			foreach ($myvarNatRule in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.NatService.NatRule) {
				if (!($EdgeGatewayXML.EdgeGateway.Configuration.GatewayInterfaces.GatewayInterface | where {$_.InterfaceType -ne "internal"} | where {$_.name -eq $myvarNatRule.GatewayNatRule.Interface.name})) {#testing if the interface used in that NAT rule is an internal interface, in which case we must remove the NAT rule for now
					$href = (Get-OrgVdcNetwork -Server $vcdConnect.Name -Name $myvarNatRule.GatewayNatRule.Interface.name).Href
                    if ($href) {
                        $myvarNatRule.GatewayNatRule.Interface.href = $href
                    }
                    else {#we haven't found the internal OrgVdcNetwork
                        OutputLogData -category "ERROR" -message "Could not find the OrgVdcNetwork $($myvarNatRule.GatewayNatRule.Interface.name) on the target vDC which is required by this EdgeGateway NAT rule: exiting"
						Exit
                    }
				}#endif interface in nat rule is internal
				else {
					$myvarInterfaceView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarNatRule.GatewayNatRule.Interface.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
					if ($myvarInterfaceView) { #check that we have found the external network
						$myvarNatRule.GatewayNatRule.Interface.href = $myvarInterfaceView.Href #update the reference to the external network with the target vCD object Url
					}#endif network view exists
					else { #we haven't found the external network
						OutputLogData -category "ERROR" -message "Could not find the external network $($myvarNatRule.GatewayNatRule.Interface.name) on the target vDC which is required by this EdgeGateway: exiting"
						Exit
					}#endelse network view exists
				}#endelse interface in nat rule is internal
			}#end foreach natrule
		}#endif natservice
		#endregion
		
		#region Load Balancer
		#let's update interface references in virtual server objects in the LoadBalancer service configuration
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService) {
			foreach ($myvarVirtualServer in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService.VirtualServer) {
				$myvarInterfaceView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarVirtualServer.Interface.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
				if ($myvarInterfaceView) { #check that we have found the external network
					$myvarVirtualServer.Interface.href = $myvarInterfaceView.Href #update the reference to the external network with the target vCD object Url
				}#endif network view exists
				else { #we haven't found the external network
					OutputLogData -category "ERROR" -message "Could not find the external network $($myvarVirtualServer.Interface.name) on the target vDC which is required in this Load Balancer Virtual Server element: exiting"
					Exit
				}#endelse network view exists
			}#end foreach dhcp pool
		}#endif GatewayDhcpService
		#endregion
		
		#region Disabled Services
		#remove other services if they are not enabled
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayIpsecVpnService) {
			if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayIpsecVpnService.IsEnabled -eq "false") {
				$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayIpsecVpnService) | Out-Null
				OutputLogData -category "INFO" -message "Removed GatewayIpsecVpnService definition because it was disabled."
			}#endif disabled
		}#endif disabled vpn service
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService) {
			if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService.IsEnabled -eq "false") {
				$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService) | Out-Null
				OutputLogData -category "INFO" -message "Removed StaticRoutingService definition because it was disabled."
			}#endif disabled
		}#endif disabled staticRouting service
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService) {
			if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService.IsEnabled -eq "false") {
		#		$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService) | Out-Null
		#		OutputLogData -category "INFO" -message "Removed LoadBalancerService definition because it was disabled."
			}#endif disabled
		}#endif disabled LoadBalancerService service
		#endregion
		
		#region Static Routes
		#let's take care of GatewayInterface href in static routes
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService) {
			OutputLogData -category "INFO" -message "Updating external network references in StaticRoutingService definition..."
			foreach ($myvarStaticRoute in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService.StaticRoute) {
				$myvarInterfaceView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarStaticRoute.GatewayInterface.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
				if ($myvarInterfaceView) { #check that we have found the external network
					$myvarStaticRoute.GatewayInterface.href = $myvarInterfaceView.Href #update the reference to the external network with the target vCD object Url
				}#endif network view exists
				else { #we haven't found the external network
					OutputLogData -category "ERROR" -message "Could not find the external network $($myvarStaticRoute.GatewayNatRule.name) on the target vDC which is required by this EdgeGateway: exiting"
					Exit
				}#endelse network view exists
			}#end foreach static route
		}#endif StaticRoutingService
		#endregion
		
		#endregion
		
		#region REST POST
		#ok, we're ready to create the organization using the REST API, let's prepare headers and the XML body
		$myvarRESTContentType = "application/vnd.vmware.admin.edgeGatewayServiceConfiguration+xml"
		$myvarRESTXMLBody = '<?xml version="1.0" encoding="UTF-8"?>' + $nl
		$myvarRESTXMLBody += $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.OuterXml | Format-Xml #that takes care of the XML body
		#we've got the content properly formatted, let's prepare the URL
		$myvarRESTUrl = getRESTUrl -lookup $myvarEdgeGatewayUrl -type $myvarRESTContentType -rel "edgeGateway:configureServices" -sessionId $vcdConnect.SessionId -Object EdgeGateway
		
		$myvarRESTHeaders = @{"Accept"="application/*+xml;version=20.0"}
		$myvarRESTHeaders += @{"Content-Type"=$myvarRESTContentType}
		$myvarRESTHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId} #that takes care of the headers
		
		#ok, we're ready to roll with the REST request
		OutputLogData -category "INFO" -message "Configuring the Edge Gateway $($EdgeGatewayXML.EdgeGateway.Name)..."
		try {
			$myvarRESTResponse = Invoke-RestMethod -Uri $myvarRESTUrl -Headers $myvarRESTHeaders -Method Post -Body $myvarRESTXMLBody -ErrorAction Stop
		}
		catch {
			OutputLogData -category "ERROR" -message "$($($_.Exception.Message))"
        	OutputLogData -category "ERROR" -message "Could not configure the Edge Gateway $($EdgeGatewayXML.EdgeGateway.Name), exiting."
			$myvarRESTFullError = RESTFailureHandling
			if ($myvarRESTFullError -match '(?<= ] )(.+)(?=" minorErrorCode)') {
				$myError = $matches[0]
				OutputLogData -category "ERROR" -message "$myError"
			} else {OutputLogData -category "ERROR" -message "$myvarRESTFullError"}
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully configured the Edge Gateway $($EdgeGatewayXML.EdgeGateway.Name)."
		#endregion
		
	}#end process
	end {
	}#end
}#end function

#function create an EdgeGateway object
function editVcdEdgeGateway {
	#input: orgVdcName, vcdConnect, EdgeGatewayXML
	#output: REST response for object creation
<#
.SYNOPSIS
  Completes the EGW configuration after the EGW has been initially created.
.DESCRIPTION
  During initial creation, we remove internal interfaces from the EGW definition and disable default routes.  Now that the EGW and OrgVdcNetworks have been created, we need to re-enable default routes.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER EdgeGatewayXML
  This the XML description of the EdgeGateway object to create.
.PARAMETER vcdConnect
  This is the connection information for the vCD instance where you want to create the object. This is obtained from a Connect-CiServer.
.EXAMPLE
  editVcdEdgeGateway -EdgeGatewayXML $EdgeGatewayXmlObject -vcdConnect (Connect-CiServer -Server vcloud.acme.com)
#>
	[CmdletBinding()]
	#region param
	param
	(
        [string] $orgName,
		[string] $orgVdcName,
		$vcdConnect,
		[Xml] $EdgeGatewayXML
	)
	#endregion
	
    begin {
	}#end begin
	process {
		
		#region XML Editing
		
		if ($rename) {
			$EdgeGatewayXML.EdgeGateway.name = $myvarNewEdgeGatewayName
		}#endif rename
		
		OutputLogData -category "INFO" -message "Processing EdgeGateway $($EdgeGatewayXML.EdgeGateway.name)..."
		
		#let's figure out which edge gateway we're working with here
		$myvarEdgeGatewayView = Search-Cloud -Server $vcdConnect.Name -QueryType EdgeGateway -Name $EdgeGatewayXML.EdgeGateway.name -ErrorAction Stop | Get-CIView
		$myvarEdgeGatewayUrl = $myvarEdgeGatewayView.href
		
		#making sure the description is not an invalid string...
		$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description) -replace "`n",',' #replacing line returns with commas
		$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description) -replace "&",''   #removing ampersand characters
		$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description) -replace "<",''   #removing < characters
		$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description) -replace ">",''   #removing > characters
		if (($EdgeGatewayXML.EdgeGateway.Description).Length -gt 128) {$EdgeGatewayXML.EdgeGateway.Description = ($EdgeGatewayXML.EdgeGateway.Description).substring(0,128)} #trimming the description string to 128 characters which is the max allowed in vCD 8.10 API
		
		#region Internal Gateway Interfaces
		#we now need to remove all internal gateway interfaces which will reference Org vCD Networks which don't exist yet, then turn off default route or the REST API won't take it. This will have have to be re-enabled manually after the object has been created.
		OutputLogData -category "INFO" -message "Updating internal interfaces hrefs..."
		[Boolean]$myvarDefaultGatewayHasBeenSet = $false #we use this variable to keep track of whether we have already set a default gateway interface as sometimes vCD 5.6 returns an incorrect XML with multiple interfaces configured as the default gateway.
        foreach ($myvarGatewayInterface in $EdgeGatewayXML.EdgeGateway.Configuration.GatewayInterfaces.GatewayInterface) { #list all gateway interfaces in the xml
			if ($myvarGatewayInterface.InterfaceType -eq "internal") { #check if this is an internal interface
				$href = (Get-Org -Server $vcdConnect.Name -Name $orgName | Get-OrgVdc -Server $vcdConnect.Name -Name $orgVdcName | Get-OrgVdcNetwork -Server $vcdConnect.Name -Name $myvarGatewayInterface.name).Href
                if ($href) {
                    $myvarGatewayInterface.Network.href = $href
                }
                else {#we haven't found the internal OrgVdcNetwork
                    OutputLogData -category "ERROR" -message "Could not find the OrgVdcNetwork $($myvarGatewayInterface.name) on the target vDC which is required by this EdgeGateway NAT rule: exiting"
					Exit
                }
			}#endif internal interface
			else { #this is not an internal interface
                ############################################################################ISSUE 9: default gateway not configured
                #here, see if default route is enabled for the external interface;
                if (($myvarGatewayInterface.UseForDefaultRoute -eq "true") -and ($myvarDefaultGatewayHasBeenSet -eq $false)) { #because vCD 8.10 requires a specific gateway to be also specified (in addition to the interface, we need to insert that tag
                    $myvarDefaultGatewayHasBeenSet = $true
                    ($myvarXMLElement = $EdgeGatewayXML.CreateElement("UseForDefaultRoute",$EdgeGatewayXML.EdgeGateway.xmlns)) | Out-Null #creating a new element in the schema of the parent XML
                    if (($myvarGatewayInterface.SubnetParticipation).Count -gt 1) {#we have more than one subnet defined on this external interface, we assign the default route to the first one
                        ($myvarGatewayInterface.SubnetParticipation[0].InsertAfter($myvarXMLElement,$myvarGatewayInterface.SubnetParticipation[0].LastChild)) | Out-Null #inserting that element where it needs to be
                        ($myvarGatewayInterface.SubnetParticipation[0].UseForDefaultRoute = "true") | Out-Null #setting a value for the element
                        OutputLogData -category "INFO" -message "Using default gateway $($myvarGatewayInterface.SubnetParticipation[0].Gateway) on interface $($myvarGatewayInterface.Name)."
                    }#endif more than one subnet
                    else {
                        ($myvarGatewayInterface.SubnetParticipation.InsertAfter($myvarXMLElement,$myvarGatewayInterface.SubnetParticipation.LastChild)) | Out-Null #inserting that element where it needs to be
                        ($myvarGatewayInterface.SubnetParticipation.UseForDefaultRoute = "true") | Out-Null #setting a value for the element
                        OutputLogData -category "INFO" -message "Using default gateway $($myvarGatewayInterface.SubnetParticipation.Gateway) on interface $($myvarGatewayInterface.Name)."
                    }#end else more than one subnet
                }#endif used for default route
                elsif (($myvarGatewayInterface.UseForDefaultRoute -eq "true") -and ($myvarDefaultGatewayHasBeenSet -eq $true)) { #this interface is defined as a default route, yet we had already another interface configured as default gw, so changing the tag on this one
                    $myvarGatewayInterface.UseForDefaultRoute = "false"
				}
                $myvarNetworkView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarGatewayInterface.Network.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
				if ($myvarNetworkView) { #check that we have found the external network
					$myvarGatewayInterface.Network.href = $myvarNetworkView.Href #update the reference to the external network with the target vCD object Url
				}#endif network view exists
				else { #we haven't found the external network
					OutputLogData -category "ERROR" -message "Could not find the external network $($myvarGatewayInterface.Network.name) on the vCloud Director instance which is required by this EdgeGateway: exiting"
					Exit
				}#endelse network view exists
			}#end else internal interface
		}#end foreach gateway interface
		#endregion 

		#region NAT rules
		#let's take care of gateway interfaces in nat rules
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.NatService) {
			OutputLogData -category "INFO" -message "Updating external network references in Nat rules..."
			foreach ($myvarNatRule in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.NatService.NatRule) {
				if (!($EdgeGatewayXML.EdgeGateway.Configuration.GatewayInterfaces.GatewayInterface | where {$_.InterfaceType -ne "internal"} | where {$_.name -eq $myvarNatRule.GatewayNatRule.Interface.name})) {#testing if the interface used in that NAT rule is an internal interface, in which case we must remove the NAT rule for now
					$href = (Get-Org -Server $vcdConnect.Name -Name $orgName | Get-OrgVdc -Server $vcdConnect.Name -Name $orgVdcName | Get-OrgVdcNetwork -Server $vcdConnect.Name -Name $myvarNatRule.GatewayNatRule.Interface.name).Href
                    if ($href) {
                        $myvarNatRule.GatewayNatRule.Interface.href = $href
                    }
                    else {#we haven't found the internal OrgVdcNetwork
                        OutputLogData -category "ERROR" -message "Could not find the OrgVdcNetwork $($myvarNatRule.GatewayNatRule.Interface.name) on the target vDC which is required by this EdgeGateway NAT rule: exiting"
						Exit
                    }
				}#endif interface in nat rule is internal
				else {
					$myvarInterfaceView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarNatRule.GatewayNatRule.Interface.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
					if ($myvarInterfaceView) { #check that we have found the external network
						$myvarNatRule.GatewayNatRule.Interface.href = $myvarInterfaceView.Href #update the reference to the external network with the target vCD object Url
					}#endif network view exists
					else { #we haven't found the external network
						OutputLogData -category "ERROR" -message "Could not find the external network $($myvarNatRule.GatewayNatRule.Interface.name) on the target vDC which is required by this EdgeGateway: exiting"
						Exit
					}#endelse network view exists
				}#endelse interface in nat rule is internal
			}#end foreach natrule
		}#endif natservice
		#endregion
		
		#region Load Balancer
		#let's update interface references in virtual server objects in the LoadBalancer service configuration
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService) {
			OutputLogData -category "INFO" -message "Updating Load Balancer interfaces hrefs..."
			foreach ($myvarVirtualServer in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService.VirtualServer) {
				$myvarInterfaceView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarVirtualServer.Interface.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
				if ($myvarInterfaceView) { #check that we have found the external network
					$myvarVirtualServer.Interface.href = $myvarInterfaceView.Href #update the reference to the external network with the target vCD object Url
				}#endif network view exists
				else { #we haven't found the external network
					OutputLogData -category "ERROR" -message "Could not find the external network $($myvarVirtualServer.Interface.name) on the target vDC which is required in this Load Balancer Virtual Server element: exiting"
					Exit
				}#endelse network view exists
			}#end foreach dhcp pool
		}#endif Load Balancer
		#endregion
		
		#region DHCP Pools
		#let's update Network references for dhcp pool if GatewayDhcpService is part of the XML description
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayDhcpService) {
			OutputLogData -category "INFO" -message "Updating network hrefs for DHCP services..."
			foreach ($myvarPool in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayDhcpService.Pool) {
				$myvarPoolNetwork = Get-OrgVdcNetwork -Server $vcdConnect.Name -Name $myvarPool.Network.name #get the network href
				$myvarPool.Network.href = $myvarPoolNetwork.Href #update the href
			}#end foreach dhcp pool
		}#endif GatewayDhcpService
		#endregion
		
		#region Disabled Services
		#remove other services if they are not enabled
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayIpsecVpnService) {
			if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayIpsecVpnService.IsEnabled -eq "false") {
				$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.GatewayIpsecVpnService) | Out-Null
				OutputLogData -category "INFO" -message "Removed GatewayIpsecVpnService definition because it was disabled."
			}#endif disabled
		}#endif disabled vpn service
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService) {
			if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService.IsEnabled -eq "false") {
				$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService) | Out-Null
				OutputLogData -category "INFO" -message "Removed StaticRoutingService definition because it was disabled."
			}#endif disabled
		}#endif disabled static routing service
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService) {
			if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService.IsEnabled -eq "false") {
				$EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.RemoveChild($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.LoadBalancerService) | Out-Null
				OutputLogData -category "INFO" -message "Removed LoadBalancerService definition because it was disabled."
			}#endif disabled
		}#endif disabled load balancer service
		#endregion
		
		#region Static Routes
		#let's take care of GatewayInterface href in static routes
		if ($EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService) {
			OutputLogData -category "INFO" -message "Updating external network references in StaticRoutingService definition..."
			foreach ($myvarStaticRoute in $EdgeGatewayXML.EdgeGateway.Configuration.EdgeGatewayServiceConfiguration.StaticRoutingService.StaticRoute) {
				$myvarInterfaceView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $myvarStaticRoute.GatewayInterface.name -ErrorAction Stop | Get-CIView #look for the external network being referenced on the target vCD
				if ($myvarInterfaceView) { #check that we have found the external network
					$myvarStaticRoute.GatewayInterface.href = $myvarInterfaceView.Href #update the reference to the external network with the target vCD object Url
				}#endif network view exists
				else { #we haven't found the external network
					OutputLogData -category "ERROR" -message "Could not find the external network $($myvarStaticRoute.GatewayNatRule.name) on the vCloud Director instance which is required by this EdgeGateway: exiting"
					Exit
				}#endelse network view exists
			}#end foreach static route
		}#endif StaticRoutingService
		#endregion
		
		#endregion
		
		#region REST POST
		#ok, we're ready to create the organization using the REST API, let's prepare headers and the XML body
		$myvarRESTContentType = "application/vnd.vmware.admin.edgeGateway+xml"
		$myvarRESTXMLBody = '<?xml version="1.0" encoding="UTF-8"?>' + $nl
		$myvarRESTXMLBody += $EdgeGatewayXML.EdgeGateway.OuterXml | Format-Xml #that takes care of the XML body
		
		#we've got the content properly formatted, let's prepare the URL
		$myvarRESTUrl = getRESTUrl -lookup $myvarEdgeGatewayUrl -type $myvarRESTContentType -rel "edit" -sessionId $vcdConnect.SessionId -Object EdgeGateway
		
		#let's get the headers ready
		$myvarRESTHeaders = @{"Accept"="application/*+xml;version=20.0"}
		$myvarRESTHeaders += @{"Content-Type"=$myvarRESTContentType}
		$myvarRESTHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId} #that takes care of the headers
		
		#ok, we're ready to roll with the REST request
		OutputLogData -category "INFO" -message "Editing the EdgeGateway $($EdgeGatewayXML.EdgeGateway.Name)..."
		try {
			$myvarRESTResponse = Invoke-RestMethod -Uri $myvarRESTUrl -Headers $myvarRESTHeaders -Method Put -Body $myvarRESTXMLBody -ErrorAction Stop
		}
		catch {
			OutputLogData -category "ERROR" -message "$($($_.Exception.Message))"
        	OutputLogData -category "ERROR" -message "Could not edit the EdgeGateway $($EdgeGatewayXML.EdgeGateway.Name) : exiting."
			$myvarRESTFullError = RESTFailureHandling
			if ($myvarRESTFullError -match '(?<= ] )(.+)(?=" minorErrorCode)') {
				$myError = $matches[0]
				OutputLogData -category "ERROR" -message "$myError"
			} else {OutputLogData -category "ERROR" -message "$myvarRESTFullError"}
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully edited the EdgeGateway $($EdgeGatewayXML.EdgeGateway.Name)."
		#endregion
	}#end process
	end {
	}#end
}#end function

#function create an OrgVdcNetwork object
function createVcdOrgVdcNetwork {
	#input: orgVdcName, vcdConnect, orgVdcNetworkXML
	#output: REST response for object creation
<#
.SYNOPSIS
  Create a vCloud Director OrgVdcNetwork object from an XML description.
.DESCRIPTION
  Create a vCloud Director OrgVdcNetwork object from an XML description. This does not include associated EdgeGateway service configuration which often needs to be re-applied after creating OrgVdcNetworks.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER orgVdcName
  This the name of the OrgVdc where you want this OrgVdcNetwork created.
.PARAMETER orgVdcNetworkXML
  This the XML description of the OrgVdcNetwork object to create.
.PARAMETER vcdConnect
  This is the connection information for the vCD instance where you want to create the object. This is obtained from a Connect-CiServer.
.EXAMPLE
  createVcdOrgVdcNetwork -orgVdcName AcmeOrg_Vdc -orgVdcNetworkXML $OrgVdcNetworkXmlObject -vcdConnect (Connect-CiServer -Server vcloud.acme.com)
#>
	[CmdletBinding()]
	#region param
	param
	(
		[string] $orgVdcName,
		$vcdConnect,
		[Xml] $orgVdcNetworkXML
	)
	#endregion
	
    begin {
	}#end begin
	process {
	
		#region XMLEditing
		#An OrgVdcNetwork needs an OrgVdc as a target, so let's prompt the user for that
		if (!$orgVdcName) {$orgVdcName = Read-Host "Please enter the name of the Organization vDC where you want to migrate this OrgVdcNetwork"}
		#Now we figure out the Url for that OrgVdc on the target
		$myvarOrgVdcUrl = (Get-OrgVdc -Server $vcdConnect.Name -Name $orgVdcName).Href
		
		#Now let's edit the EdgeGateway reference if this is a routed network
		if ($orgVdcNetworkXML.OrgVdcNetwork.Configuration.FenceMode -eq "natRouted") {
			OutputLogData -category "INFO" -message "This is a routed network, updating the Edge Gateway href in the XML description..."
			$myvarEdgeGatewayView = Search-Cloud -Server $vcdConnect.Name -QueryType EdgeGateway -Name $myvarNewEdgeGatewayName -ErrorAction Stop | Get-CIView
			$orgVdcNetworkXML.OrgVdcNetwork.EdgeGateway.href = $myvarEdgeGatewayView.Href
		}#endif routed network
		
		#If this is a bridged network, we need to update the parent network reference
		if ($orgVdcNetworkXML.OrgVdcNetwork.Configuration.FenceMode -eq "bridged") {
			OutputLogData -category "INFO" -message "This is a bridged network, updating the Parent Network href in the XML description..."
			if (!($myvarNetworkView = Search-Cloud -Server $vcdConnect.Name -QueryType ExternalNetwork -Name $($orgVdcNetworkXML.OrgVdcNetwork.Configuration.ParentNetwork.name) -ErrorAction Stop | Get-CIView)) {
            OutputLogData -category "ERROR" -message "Could not find the External Network $($orgVdcNetworkXML.OrgVdcNetwork.Configuration.ParentNetwork.name) on the target vDC. Please create it first: exiting."
                exit
            }#endif does the external network exist			
            $orgVdcNetworkXML.OrgVdcNetwork.Configuration.ParentNetwork.href = $myvarNetworkView.Href
		}#endif bridged network

		#endregion

		
		#region REST POST
		#ok, we're ready to create the organization using the REST API, let's prepare headers and the XML body
		$myvarRESTContentType = "application/vnd.vmware.vcloud.orgVdcNetwork+xml"
		$myvarRESTXMLBody = '<?xml version="1.0" encoding="UTF-8"?>' + $nl
		$myvarRESTXMLBody += $orgVdcNetworkXML.OrgVdcNetwork.OuterXml | Format-Xml #that takes care of the XML body
		$myvarRESTHeaders = @{"Accept"="application/*+xml;version=20.0"}
		$myvarRESTHeaders += @{"Content-Type"=$myvarRESTContentType}
		$myvarRESTHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId} #that takes care of the headers
		#we've got the content properly formatted, let's prepare the URL
		$myvarRESTUrl = getRESTUrl -lookup $myvarOrgVdcUrl -type $myvarRESTContentType -rel "add" -sessionId $vcdConnect.SessionId -Object AdminVdc
		
		#ok, we're ready to roll with the REST request
		OutputLogData -category "INFO" -message "Creating the OrgVdcNetwork $($orgVdcNetworkXML.OrgVdcNetwork.Name)..."
		try {
			$myvarRESTResponse = Invoke-RestMethod -Uri $myvarRESTUrl -Headers $myvarRESTHeaders -Method Post -Body $myvarRESTXMLBody -ErrorAction Stop
		}
		catch {
			OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
        	OutputLogData -category "ERROR" -message "Could not create the OrgVdcNetwork $($orgVdcNetworkXML.OrgVdcNetwork.Name): exiting."
			$myvarRESTFullError = RESTFailureHandling
			if ($myvarRESTFullError -match '(?<= ] )(.+)(?=" minorErrorCode)') {
				$myError = $matches[0]
				OutputLogData -category "ERROR" -message "$myError"
			} else {OutputLogData -category "ERROR" -message "$myvarRESTFullError"}
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully created the OrgVdcNetwork $($orgVdcNetworkXML.OrgVdcNetwork.Name)."
		#endregion
	}#end process
	end {
	}#end
}#end function

#function create an ExternalNetwork object
function createVcdExternalNetwork {
	[CmdletBinding()]
	#input: vcdConnect, ExternalNetworkXML, vcenter, dvportgroup
	#output: REST response for object creation
<#
.SYNOPSIS
  Create a vCloud Director ExternalNetwork object from an XML description.
.DESCRIPTION
  Create a vCloud Director ExternalNetwork object from an XML description.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER ExternalNetworkXML
  This the XML description of the EdgeGateway object to create.
.PARAMETER vcdConnect
  This is the connection information for the vCD instance where you want to create the object. This is obtained from a Connect-CiServer.
.PARAMETER vcenter
  This is the name of the vCenter/ProviderVdc where you want the external network to exist.
.PARAMETER dvportgroup
  This is the name of the dvportgroup in the vcenter/ProviderVdc where this external network will be attached.
.EXAMPLE
  createVcdExternalNetwork -ExternalNetworkXML $ExternalNetworkXmlObject -vcdConnect (Connect-CiServer -Server vcloud.acme.com) -vcenter MyProviderVdc -dvportgroup dvpg_vlan3
#>
	#region param
	param
	(
		$vcdConnect,
		[Xml] $ExternalNetworkXML,
        [string] $vcenter,
        [string] $dvportgroup
	)
	#endregion
	
    begin {
	}#end begin
	process {
		#region XML Editing
		#external networks need a vcenter server and a portgroup, so let's prompt for that information if necessary

        #region vcenter href
            if (!$vcenter) {
                OutputLogData -category "WARNING" -message "You are trying to migrate an External Network, which requires a vCenter server and a dvportgroup"
			    if ((Search-Cloud -Server $vcdConnect.Name -QueryType VirtualCenter).Count -ne 1) { #there is more than 1 vCenter
				    $myvarvCenterName = Read-Host "Enter the vCenter server name for this external network"
				    #let's get the vCenter server object view and update the href
				    try {
					    $myvarvCenterView = Search-Cloud -Server $vcdConnect.Name -QueryType VirtualCenter -Name $myvarvCenterName -ErrorAction Stop | Get-CIView
				    }#end try vcenter
				    catch {
					    OutputLogData -category "ERROR" -message "$($($_.Exception.Message))"
		        	    OutputLogData -category "ERROR" -message "Could not find vCenter $myvarvCenterName, exiting."
					    Exit
				    }#end catch try vcenter
			    }#endif more than one vcenter
			    else { #there is only one vCenter
				    try {
					    $myvarvCenterView = Search-Cloud -Server $vcdConnect.Name -QueryType VirtualCenter -ErrorAction Stop | Get-CIView
				    }#end try vcenter
				    catch {
					    OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
		        	    OutputLogData -category "ERROR" -message "Could not find vCenter $myvarvCenterName, exiting."
					    Exit
				    }#end catch try vcenter
			    }#endelse more than one vcenter
            }#endif not vcenter
			########FIND OUT WHY CATCH IS NOT WORKING
			else { #a vcenter has been specified, let's get the object
                try {
					$myvarvCenterView = Search-Cloud -Server $vcdConnect.Name -QueryType VirtualCenter -Name $myvarvCenterName -ErrorAction Stop | Get-CIView
				}#end try vcenter
				catch
				{
					OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
		        	OutputLogData -category "ERROR" -message "Could not find vCenter $vcenter, exiting."
					Exit
				}#end catch try vcenter
            }#endelse not vcenter
			
            #update the vcenter href in the external network XML description
            $ExternalNetworkXML.VMWExternalNetwork.VimPortGroupRef.VimServerRef.href = $myvarvCenterView.Href

            #endregion

        #region dvportgroup href
            if (!$dvportgroup) {
			    $dvPortGroup = Read-Host "Enter the dvportgroup name for this external network"
            }#endif not dvportgroup
            #a dvportgroup was specified
		    #now let's get the portgroup and update the MoRef
		    try
		    {
			    $myvardvPortGroupObject = Search-Cloud -Server $vcdConnect.Name -QueryType Portgroup -Name $dvPortGroup
		    }#end try portgroup
		    catch
		    {
			    Write-Warning $($_.Exception.Message)
        	    OutputLogData -category "ERROR" -message "Could not find dvPortGroup $dvPortGroup, exiting."
			    Exit
		    }#end catch try portgroup

            #update the dvportgroup href in the external network XML description
			$ExternalNetworkXML.VMWExternalNetwork.VimPortGroupRef.MoRef = $myvardvPortGroupObject.MoRef
            #endregion 			

        #region ipscopes
			#remove IpScopes allocations and suballocations for now as the EdgeGateways will not exist
			foreach ($myvarIpScope in $ExternalNetworkXML.VMWExternalNetwork.Configuration.IpScopes.IpScope)
			{
				($myvarIpScope.AllocatedIpAddresses).RemoveAll()
				($myvarIpScope.SubAllocations).RemoveAll()
			}#end foreach ip scope
            #endregion ipscopes
			
        #endregion
			
		#region REST POST
		#ok, we're ready to create the external network using the REST API
		$myvarRESTContentType = "application/vnd.vmware.admin.vmwexternalnet+xml"
		$myvarRESTXMLBody = '<?xml version="1.0" encoding="UTF-8"?>' + $nl
		$myvarRESTXMLBody += $ExternalNetworkXML.VMWExternalNetwork.OuterXml | Format-Xml #that takes care of the XML body
		$myvarRESTHeaders = @{"Accept"="application/*+xml;version=20.0"}
		$myvarRESTHeaders += @{"Content-Type"=$myvarRESTContentType}
		$myvarRESTHeaders += @{"x-vcloud-authorization"=$vcdConnect.SessionId} #that takes care of the headers
		#we've got the content properly formatted, let's prepare the URL
		$myvarRESTUrl = getRESTUrl -lookup ($vcdConnect.HRef + "admin/extension") -type $myvarRESTContentType -rel "add" -sessionId $vcdConnect.SessionId -Object VMWExtension
		#ok, we're ready to roll with the REST request
		OutputLogData -category "INFO" -message "Creating the External Network $($ExternalNetworkXML.VMWExternalNetwork.Name)..."
		try
		{
			$myvarRESTResponse = Invoke-RestMethod -Uri $myvarRESTUrl -Headers $myvarRESTHeaders -Method Post -Body $myvarRESTXMLBody -ErrorAction Stop
		}
		catch
		{
			OutputLogData -category "ERROR" -message "$($_.Exception.Message)"
	        OutputLogData -category "ERROR" -message "Could not create the External Network $($ExternalNetworkXML.VMWExternalNetwork.Name) : exiting."
			$myvarRESTFullError = RESTFailureHandling
			if ($myvarRESTFullError -match '(?<= ] )(.+)(?=" minorErrorCode)') {
				$myError = $matches[0]
				OutputLogData -category "ERROR" -message "$myError"
			} else {OutputLogData -category "ERROR" -message "$myvarRESTFullError"}
			Exit
		}
		OutputLogData -category "INFO" -message "Successfully created the External Network $($ExternalNetworkXML.VMWExternalNetwork.Name)."
		#endregion
	}#end process
	end {
	}#end
}#end function

#function promptUserList
function promptUserList {
    #input: title, message, options
	#output: selected option
<#
.SYNOPSIS
  Creates a dialog box with selectable options from an array of objects.
.DESCRIPTION
  Creates a dialog box with selectable options from an array of objects.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER title
  This the title of the prompt window.
.PARAMETER message
  This is the message displayed in the prompt window which precedes the selectable options.
.PARAMETER options
  This is an array of selectable options.
.EXAMPLE
  promptUseList -title $title -message $message -options $options
#>
	[CmdletBinding()]
	#region param
	param
	(
		[string] $title,
        [string] $message,
        $options
	)
	#endregion
	
    begin {
        $selectableOptions = @()
	}#end begin
	process {
        foreach ($option in $options) {
            $selectableOption = New-Object System.Management.Automation.Host.ChoiceDescription "$option"
            $selectableOptions += $selectableOption
        }#end foreach option

        $menu = [System.Management.Automation.Host.ChoiceDescription[]]($selectableOptions)

        $result = $host.ui.PromptForChoice($title, $message, $options, 0) 
    }#end process
    end {
    }#end
}#end function

#function RESTFailureHandling
function RESTFailureHandling {
$global:helpme = $body
$global:helpmoref = $moref
$global:result = $_.Exception.Response.GetResponseStream()
$global:reader = New-Object System.IO.StreamReader($global:result)
$global:responseBody = $global:reader.ReadToEnd();

return $global:responsebody

break
}

#function PromptToContinue
function PromptToContinue {
    $input = read-host "Do you want to continue and create the EdgeGateway and the OrgVdcNetworks? Please write yes or no and press Enter"

    switch ($input) `
    {
        'no' {
            OutputLogData -category "WARNING" -message "You chose NOT to continue: exiting!"
			Exit
        }

        'yes' {
            OutputLogData -category "INFO" -message "You chose to continue script execution."
        }

        default {
            OutputLogData -category "ERROR" "You may only answer yes or no, please try again."
            PromptToContinue
        }
    }
}

#endregion

#region Prep-work

# get rid of annoying error messages
if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}

#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 10/12/2016 sb   Initial release by stephane.bourdeaud@nutanix.com
################################################################################
'@
$myvarScriptName = ".\migrate-vCDObject.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}

#let's make sure the VIToolkit is being used
if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
. “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” | Out-Null
} 

#endregion

#region Variables
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
	if ((!$import) -and (!$sourcevcd)) {$sourcevcd = read-host "Enter the hostname or IP address of the source vCD server"}
	if ($sourcevcd -and (!$sourceCredentials)) {$sourceCredentials = Get-Credential -Message "Enter credentials for the source vCloud"}
	if (!$targetvcd) {$targetvcd = read-host "Enter the hostname or IP address of the target vCD server"}
	if (!$targetCredentials) {$targetCredentials = Get-Credential -Message "Enter credentials for the target vCloud"}
	if ((!$import) -and (!$objectType)) {$objectType = Read-Host "Enter the type of object to migrate"}
	if ((!$import) -and (!$objectName)) {$objectName = Read-Host "Enter the name of the object to migrate"}
	
	#Misc Global Variables
	$myvarListOfEGW = @() #we use this variable to keep track of the Edge Gateways we create so that we may re-apply their configuration later on
	
	#Static Variables
    
        #These static variables are for configuring allocation of resources on the OrgVdc. If you want to preserve the source object config, just specify a value of "source"
        $ResourceGuaranteedMemory = 0.10
        $ResourceGuaranteedCpu = "source"	

#endregion

#region Processing
#########################
##   main processing   ##
#########################
	OutputLogData -category "INFO" -message "Ignoring invalid ssl certificates..."
	IgnoreSSL  #let's ignore invalide SSL certificates
	
	#region Import from XML
	if ($import) { #we're dealing with an XML file import rather than a source vCD server
		
		OutputLogData -category "WARNING" -message "XML import is currently incomplete. Use with caution!"
		
		#region Process source XML file
		try #let's make sure we can import the XML file content
		{
			$myvarXMLImport = Import-Clixml $import -ErrorAction Stop
		}#end try xml import
		catch
		{
			Write-Warning $($_.Exception.Message)
        	OutputLogData -category "ERROR" -message "Could not read the $import XML file, exiting."
			Exit
		}#end catch xml import error
		
		#let's determine which type of object we are looking at
		if ($myvarXMLImport.EdgeGateway) {$objectType = "EdgeGateway"}
		if ($myvarXMLImport.VMWExternalNetwork) {$objectType = "ExternalNetwork"}
		if ($myvarXMLImport.AdminOrg) {$objectType = "Organization"}
		if ($myvarXMLImport.AdminVdc) {$objectType = "OrgVdc"}
		if ($myvarXMLImport.CatalogItem) {$objectType = "CatalogItem"}
		if ($myvarXMLImport.AdminCatalog) {$objectType = "Catalog"}
		if ($myvarXMLImport.OrgVdcNetwork) {$objectType = "OrgVdcNetwork"}
		if ($myvarXMLImport.User) {$objectType = "AdminUser"}
		#endregion
		
		#region Create object on target

		#region Connect to target vcd
		OutputLogData -category "INFO" -message "Connecting to the target vCloud Director instance $vcd..."
		$myvarTargetVcdConnect = connectVcd -Credentials $targetCredentials -Vcd $targetvcd
		OutputLogData -category "INFO" -message "Connected to the target vCloud Director OK"
		#endregion
		
		#region EdgeGateway
		if ($objectType -eq "EdgeGateway")
		{
			if ($gwservices) {
				setVcdEdgeGatewayServiceConfiguration -EdgeGatewayXML $myvarXMLImport -vcdConnect $myvarTargetVcdConnect
			}#endif gwservices
			else {
				#we now look at the EdgeGateway node to determine the name of the EdgeGateway for this network, then see if it already exists on the target
				if (!(getVcdObject -name $myvarXMLImport.EdgeGateway.name -type EdgeGateway -vcdConnect $myvarTargetVcdConnect)) {
					createVcdEdgeGateway -vcdconnect $myvarTargetVcdConnect -EdgeGatewayXML $myvarXMLImport
				}#end if EGW does not exist on target
				else {#EGW already exists on target
					OutputLogData -category "WARNING" -message "The Edge Gateway $($myvarXMLImport.EdgeGateway.name) already exists on $targetvcd : skipping creation."
				}#end else EGW already exists on target
			}#end else gwservices
		}#endif EdgeGateway
		#endregion
		
		#region ExternalNetwork
		if ($objectType -eq "ExternalNetwork")
		{
            #check to see if the object does not already exist on the target, otherwise create it
            if (!(getVcdObject -name $myvarXMLImport.VMWExternalNetwork.name -type ExternalNetwork -vcdConnect $myvarTargetVcdConnect)) {
				createVcdExternalNetwork -vcdConnect $myvarTargetVcdConnect -ExternalNetworkXML $myvarXMLImport
			}#end if External Network does not exist on target
			else {#External network already exists on target
				OutputLogData -category "WARNING" -message "The External Network $($myvarXMLImport.VMWExternalNetwork.name) already exists on $targetvcd : skipping creation."
			}#end else External Network already exists on target
		}#endif external network	
		#endregion
		
		#region Organization
		if ($objectType -eq "Organization") {
                        
            #check to see if the object does not already exist on the target, otherwise create it
            if (!(getVcdObject -name $myvarXMLImport.AdminOrg.name -type Organization -vcdConnect $myvarTargetVcdConnect)) {
				createVcdOrg -vcdConnect $myvarTargetVcdConnect -OrgXML $myvarXMLImport
			}#end if organization does not exist on target
			else {#organization already exists on target
				OutputLogData -category "WARNING" -message "The Organization $($myvarXMLImport.AdminOrg.name) already exists on $targetvcd : skipping creation."
			}#end else Organization already exists on 

        }#endif organization
		#endregion
		
		#region OrgVdc
		if ($objectType -eq "OrgVdc") {
            createVcdOrgVdc -vcd $targetvcd -OrgVdcXML $myvarXMLImport

            if (!(Get-OrgVdc -Server $targetvcd -Name $myvarXMLImport.AdminVdc.name)) {#OrgVdc does not already exist on target
				createVcdOrgVdc -vcd $targetvcd -OrgVdcXML $myvarXMLImport
			}#endif OrgVdc does not exist on target
			else {#OrgVdc already exists on target
				OutputLogData -category "WARNING" -message "The OrgVdc $($myvarXMLImport.AdminVdc.name) already exists on $targetvcd : skipping creation."
			}#end else OrgVdc already exists on target
        }#endif OrgVdc
		#endregion
		
		#region OrgVdcNetwork
		if ($objectType -eq "OrgVdcNetwork") {
			if (!(Get-OrgVdcNetwork -Server $targetvcd -Name $myvarXMLImport.OrgVdcNetwork.name)) {#OrgVdcNetwork does not already exist on target
				createVcdOrgVdcNetwork -vcdconnect $myvarTargetVcdConnect -OrgVdcNetworkXML $myvarXMLImport
				Do {
					OutputLogData -category "INFO" -message "Waiting for the OrgVdcNetwork $($myvarXMLImport.OrgVdcNetwork.name) to be created and ready..."
					Start-Sleep -Seconds 5
				} While ((Get-OrgVdcNetwork -Server $targetvcd -Name $myvarXMLImport.OrgVdcNetwork.name).ExtensionData.Status -ne 1)
			}#endif OrgVdcNetwork does not exist on target
			else {#OrgVdcNetwork already exists on target
				OutputLogData -category "WARNING" -message "The OrgVdcNetwork $($myvarXMLImport.OrgVdcNetwork.name) already exists on $targetvcd : skipping creation."
			}#end else OrgVdc already exists on target
		}#endif OrgVdcNetwork
		#endregion
		
		#region AdminUser
		if ($objectType -eq "AdminUser") {

            #create the object on target if it does not laready exist
            if (!(getVcdObject -name $myvarXMLImport.User.Name -type AdminUser -vcdConnect $myvarTargetVcdConnect)) {
				createVcdUser -vcdconnect $myvarTargetVcdConnect -userXML $myvarXMLImport
			}#end if user does not exist on target
			else {#user already exists on target
				OutputLogData -category "WARNING" -message "The User $($myvarXMLImport.User.Name) already exists on $targetvcd : skipping creation."
			}#end else user already exists on target

        }#endif AdminUser
		#endregion
		
		#endregion
		
	}#endif import
	#endregion
	
	#region Import from a source vCloud Director Instance
	else { #we're dealing with a source vCD server

		#region Connect to Source vCloud Director
		#connect to source vcd
		$myvarSourceVcdConnect = connectVcd -Credentials $sourceCredentials -Vcd $sourcevcd
		#endregion

		#region Connect to the target vCD instance
		$myvarTargetVcdConnect = connectVcd -Credentials $targetCredentials -Vcd $targetvcd
		#endregion
		
		OutputLogData -category "INFO" -message "Searching for $objectType $objectName..."


        ##############################################################################################################

		#region Organization
		if ($objectType -eq "Organization") {
			
			#region Get the organization object
			$myvarOrgXML = getVcdObject -type $objectType -name $objectName -vcdConnect $myvarSourceVcdConnect
			if (!$myvarOrgXML) {
				OutputLogData -category ERROR -message "Could not find $objectType with name $objectName on $($myvarSourceVcdConnect.name): exiting!"
				Remove-Variable * -ErrorAction SilentlyContinue
				Exit
			}#endif no OrgXML
			#endregion
						
			#region Create the organization object
			OutputLogData -category "INFO" -message "---------------- Dealing with the Organization object ----------------"
			if ($rename) {#check to see if user wants to rename objects
				if ($newOrgName) {[string]$myvarNewOrgName = $newOrgName} else {[string]$myvarNewOrgName = Read-Host "Enter the new name for the organization object"}
			}#endif rename
			else {
				$myvarNewOrgName = $objectName
			}#endelse rename
			if (!(Search-Cloud -Server $targetvcd -QueryType Organization -Name $myvarNewOrgName)) {
				createVcdOrg -vcdConnect $myvarTargetVcdConnect -OrgXML $myvarOrgXML
                OutputLogData -category "INFO" -message "Waiting for 10 seconds after Org creation..."
				Start-Sleep 10
			}#endif org does not already exist on target
			else {#org already exists on target
				OutputLogData -category "WARNING" -message "The organization $($myvarNewOrgName) already exists on $targetvcd : skipping creation."
			}#end else org already exists on target
            OutputLogData -category "INFO" -message "Retrieving again the Org XML from the source..."
			$myvarOrgXML = getVcdObject -type $objectType -name $objectName -vcdConnect $myvarSourceVcdConnect
            #endregion
			
			#region Re-create users in the organization
			OutputLogData -category "INFO" -message "---------------- Dealing with the User object(s) ----------------"
			#loop thru users
			foreach ($myvarUser in $myvarOrgXML.AdminOrg.Users.UserReference) {
				#extract user definition
				$myvarUserXML = getVcdObject -href $myvarUser.href -hrefType $myvarUser.type -vcdConnect $myvarSourceVcdConnect
				#check that the user role exists
				$myvarRoleView = Search-Cloud -Server $myvarTargetVcdConnect.Name -QueryType Role -Name $myvarUserXML.User.Role.name -ErrorAction Stop | Get-CIView
				if (!$myvarRoleView) {
					#if not, retrieve the user role from source
					$myvarRoleXML = getVcdObject -type Role -name $myvarUserXML.User.Role.Name -vcdConnect $myvarSourceVcdConnect
					createVcdRole -vcdConnect $myvarTargetVcdConnect -roleXML $myvarRoleXML	
				}#endif no role view
				#create user if does not already exist
				$myvarTargetOrgXML = getVcdObject -type $objectType -name $myvarNewOrgName -vcdConnect $myvarTargetVcdConnect #we are retrieving the XML object for the Org on the target vCD in order to compare users
				#######backup line#this gave false positive when user with same name already existed in another org#if (!(Search-Cloud -Server $targetvcd -QueryType AdminUser -Name $myvarUserXML.User.name)) {
				if (!($myvarTargetOrgXML.AdminOrg.Users.UserReference | where {$_.Name -eq $myvarUserXML.User.name})) {
					createVcdUser -orgname $myvarNewOrgName -vcdconnect $myvarTargetVcdConnect -userXML $myvarUserXML
				}#endif user does not already exist on target
				else {#user already exists on target
					OutputLogData -category "WARNING" -message "The user $($myvarUserXML.User.name) already exists on $targetvcd : skipping creation."
				}#end else user already exists on target
			}#end foreach user
			#endregion
			
			#region create the OrgVdc object
			OutputLogData -category "INFO" -message "---------------- Dealing with the OrgVdc object ----------------"
			foreach ($myvarOrgVdc in $myvarOrgXML.AdminOrg.Vdcs.Vdc) {
				#retrieve the OrgVdc XML description from the source
				$myvarOrgVdcXML = getVcdOrgVdc -org $myvarOrgXML.AdminOrg.Name -orgVdcName $myvarOrgVdc.Name -vcdConnect $myvarSourceVcdConnect
				if ($rename) {#check to see if user wants to rename objects
					if ($NewOrgVdcName) {[string]$myvarNewOrgVdcName = $NewOrgVdcName} else {[string]$myvarNewOrgVdcName = Read-Host "Enter the new name for the OrgVdc object"}
				}#endif rname
				else {
					$myvarNewOrgVdcName = $myvarOrgVdc.Name
				}#endelse rename
				#create the OrgVdc object on the target if it does not already exist
				if (!(Get-Org -Server $targetvcd -Name $myvarNewOrgName | Get-OrgVdc -Server $targetvcd -Name $myvarNewOrgVdcName)) {
					createVcdOrgVdc -orgName $myvarNewOrgName -OrgVdcXML $myvarOrgVdcXML -vcd $targetvcd
                    OutputLogData -category "INFO" -message "Waiting for 10 seconds after OrgVdc configuration..."
				    Start-Sleep 10
				}#endif OrgVdc does not already exist
				else {#OrgVdc already exists on target
					OutputLogData -category "WARNING" -message "The OrgVdc $myvarNewOrgVdcName already exists on $targetvcd : skipping creation."
				}#end else OrgVdc already exists on target
			}#end foreach OrgVdc
			#endregion
			
			#region create EdgeGateway and OrgVdcNetwork objects
			PromptToContinue
            OutputLogData -category "INFO" -message "---------------- Dealing with the OrgVdc and EdgeGateway objects ----------------"
			#to figure out the EdgeGateway, we need to look at Networks within the Org object
			foreach ($myvarNetwork in $myvarOrgXML.AdminOrg.Networks.Network) {
				
				#we retrieve the XML description of the network object from the source
				$myvarNetworkXML = getVcdOrgVdcNetwork -orgName $myvarOrgXML.AdminOrg.Name -orgVdcName $myvarOrgVdcXML.AdminVdc.Name -orgVdcNetworkName $myvarNetwork.name -vcdConnect $myvarSourceVcdConnect
				
				#region EdgeGateway
				#we now look at the EdgeGateway node to determine the name of the EdgeGateway for this network, then see if it already exists on the target
				if ($myvarNetworkXML.OrgVdcNetwork.EdgeGateway) {
                    ########BUG: insert here fix to deal with duplicate Edge Gateway names
					if (!($myvarListOfEGW | where {$_.sourceName -eq $myvarNetworkXML.OrgVdcNetwork.EdgeGateway.name})) {
						$myvarEdgeGatewayXML = getVcdObject -name $myvarNetworkXML.OrgVdcNetwork.EdgeGateway.name -type EdgeGateway -vcdConnect $myvarSourceVcdConnect
						
						if ($rename) {#check to see if user wants to rename objects
							if ($NewEdgeName) {[string]$myvarNewEdgeGatewayName = $NewEdgeName} else {[string]$myvarNewEdgeGatewayName = Read-Host "Enter the new name for the Edge Gateway object currently called $($myvarNetworkXML.OrgVdcNetwork.EdgeGateway.name)"}
							$myvarEdgeNames = @{“sourceName”=$myvarNetworkXML.OrgVdcNetwork.EdgeGateway.name;”targetName”=$myvarNewEdgeGatewayName}
						}#endif rename
						else {
							$myvarNewEdgeGatewayName = $myvarNetworkXML.OrgVdcNetwork.EdgeGateway.name
							$myvarEdgeNames = @{“sourceName”=$myvarNetworkXML.OrgVdcNetwork.EdgeGateway.name;”targetName”=$myvarNetworkXML.OrgVdcNetwork.EdgeGateway.name}
						}#endelse rename
						
						$myvarListOfEGW += $myvarEdgeNames #Adding this EdgeGateway to the list of EGW processed for later use
						
						if (!(getVcdObject -name $myvarNewEdgeGatewayName -type EdgeGateway -vcdConnect $myvarTargetVcdConnect)) {
							#EGW does not exist on target, so we need to create it
							createVcdEdgeGateway -orgVdcName $myvarNewOrgVdcName -vcdconnect $myvarTargetVcdConnect -EdgeGatewayXML $myvarEdgeGatewayXML
							Do {
								OutputLogData -category "INFO" -message "Waiting for the EdgeGateway $myvarNewEdgeGatewayName to be created and ready..."
								Start-Sleep -Seconds 5
							} While ((Search-Cloud -QueryType EdgeGateway -Server $myvarTargetVcdConnect.Name -Name $myvarNewEdgeGatewayName).GatewayStatus -ne "READY")
							Start-Sleep -Seconds 20
						}#end if EGW does not exist on target
						else {#EGW already exists on target
							OutputLogData -category "WARNING" -message "The Edge Gateway $myvarNewEdgeGatewayName already exists on $targetvcd : skipping creation."
						}#end else EGW already exists on target
					}#end else EGW has already been processed
					else {#EGW already exists on target
						OutputLogData -category "WARNING" -message "The Edge Gateway $myvarNewEdgeGatewayName has already been processed : skipping creation."
					}#end else EGW already exists on target
				}#endif network has an edge gateway
				#endregion
				
				#region OrgVdcNetwork
				#the edge gateway is there, so it's safe to add the network if it's not already there
				if (!(Get-Org -Server $targetvcd -Name $myvarNewOrgName | Get-OrgVdc -Server $targetvcd -Name $myvarNewOrgVdcName | Get-OrgVdcNetwork -Server $targetvcd -Name $myvarNetwork.name)) {#OrgVdcNetwork does not already exist on target
					createVcdOrgVdcNetwork -vcdconnect $myvarTargetVcdConnect -OrgVdcNetworkXML $myvarNetworkXML -orgVdcName $myvarNewOrgVdcName
					Do {
						OutputLogData -category "INFO" -message "Waiting for the OrgVdcNetwork $($myvarNetwork.name) to be created and ready..."
						Start-Sleep -Seconds 5
					} While ((Get-Org -Server $targetvcd -Name $myvarNewOrgName | Get-OrgVdc -Server $targetvcd -Name $myvarNewOrgVdcName | Get-OrgVdcNetwork -Server $targetvcd -Name $myvarNetwork.name).ExtensionData.Status -ne 1)
					Start-Sleep -Seconds 20
				}#endif OrgVdcNetwork does not exist on target
				else {#OrgVdcNetwork already exists on target
					OutputLogData -category "WARNING" -message "The OrgVdcNetwork $($myvarNetwork.name) already exists on $targetvcd : skipping creation."
				}#end else OrgVdc already exists on target
				#endregion
				
			}#end foreach network in org
			#endregion
			
			#region re-apply EdgeGateway configuration
			#because some EGW network services require networks to be present, we now need to re-apply the EGW configuration
			foreach ($myvarEGW in $myvarListOfEGW) {
				$myvarEdgeGatewayXML = getVcdObject -name $myvarEGW.sourceName -type EdgeGateway -vcdConnect $myvarSourceVcdConnect
				$myvarNewEdgeGatewayName = $myvarEGW.targetName
				if ($myvarEdgeGatewayXML) {
					OutputLogData -category "INFO" -message "Waiting for 30 seconds before re-applying the Edge Gateway configuration..."
					Start-Sleep 30
					editVcdEdgeGateway -vcdconnect $myvarTargetVcdConnect -EdgeGatewayXML $myvarEdgeGatewayXML -orgName $myvarNewOrgName -orgVdcName $myvarNewOrgVdcName
				}#endif EdgeGatewayXML
				else {
					OutputLogData -category "WARNING" -message "There was no EdgeGateway XML object so we could not re-apply the configuration!"
				}
			}
			#endregion
			
		}#endif Organization
		#endregion
		
        ##############################################################################################################



		#region OrgVdc
		if ($objectType -eq "OrgVdc") {
			#get the XML description from the source
            if (!$orgName) {$orgName = Read-Host "Please enter the name of the Organization for this OrgVdc on the source vCD instance"}
			$myvarOrgVdcXML = getVcdOrgVdc -org $orgName -orgVdcName $objectName -vcdConnect $myvarSourceVcdConnect
			#create the OrgVdc if it does not already exist on the target
			if (!(Get-Org -Name $orgName | Get-OrgVdc -Server $targetvcd -Name $myvarOrgVdcXML.AdminVdc.Name)) {
				createVcdOrgVdc -OrgVdcXML $myvarOrgVdcXML -vcd $targetvcd
			}#endif OrgVdc does not already exist
			else {#OrgVdc already exists on target
				OutputLogData -category "WARNING" -message "The OrgVdc $($myvarOrgVdcXML.AdminVdc.Name) already exists on $targetvcd : skipping creation."
			}#end else OrgVdc already exists on target			
		}#endif OrgVdc
		#endregion
		
		#region OrgVdcNetwork
		if ($objectType -eq "OrgVdcNetwork") {
			#extract OrgVdcNetwork XML description
			$myvarOrgVdcNetworkXML = getVcdOrgVdcNetwork -orgVdcNetworkName $objectName -vcdConnect $myvarSourceVcdConnect
			#create OrgVdcNetwork object on target
			if (!(Get-OrgVdcNetwork -Server $targetvcd -Name $myvarOrgVdcNetworkXML.OrgVdcNetwork.name)) {#OrgVdcNetwork does not already exist on target
				createVcdOrgVdcNetwork -vcdconnect $myvarTargetVcdConnect -OrgVdcNetworkXML $myvarOrgVdcNetworkXML
				Do {
					OutputLogData -category "INFO" -message "Waiting for the OrgVdcNetwork $($myvarOrgVdcNetworkXML.OrgVdcNetwork.name) to be created and ready..."
					Start-Sleep -Seconds 5
				} While ((Get-OrgVdcNetwork -Server $targetvcd -Name $myvarOrgVdcNetworkXML.OrgVdcNetwork.name).ExtensionData.Status -ne 1)
				Start-Sleep -Seconds 20
			}#endif OrgVdcNetwork does not exist on target
			else {#OrgVdcNetwork already exists on target
				OutputLogData -category "WARNING" -message "The OrgVdcNetwork $($myvarOrgVdcNetworkXML.OrgVdcNetwork.name) already exists on $targetvcd : skipping creation."
			}#end else OrgVdc already exists on target
		}#endif OrgVdcNetwork
		#endregion
		
		#region AdminUser
		if ($objectType -eq "AdminUser") {
			#extract user definition
			$myvarUserXML = getVcdObject -name $objectName -type AdminUser -vcdConnect $myvarSourceVcdConnect
			            
            #create the object on target if it does not laready exist
            if (!(getVcdObject -name $objectName -type AdminUser -vcdConnect $myvarTargetVcdConnect)) {
				createVcdUser -vcdconnect $myvarTargetVcdConnect -userXML $myvarUserXML
			}#end if user does not exist on target
			else {#user already exists on target
				OutputLogData -category "WARNING" -message "The User $objectName already exists on $targetvcd : skipping creation."
			}#end else user already exists on target
		}#endelseif AdminUser
		#endregion
		
		#region EdgeGateway
		if ($objectType -eq "EdgeGateway") {
			#retrieve the XML description for that object from the source
			$myvarEdgeGatewayXML = getVcdObject -name $objectName -type EdgeGateway -vcdConnect $myvarSourceVcdConnect
			
			if ($rename) {#check to see if user wants to rename objects
				if ($NewEdgeName) {[string]$myvarNewEdgeGatewayName = $NewEdgeName} else {[string]$myvarNewEdgeGatewayName = Read-Host "Enter the new name for the Edge Gateway object currently called $($myvarNetworkXML.OrgVdcNetwork.EdgeGateway.name)"}
			}#endif rename
			else {
				$myvarNewEdgeGatewayName = $myvarNetworkXML.OrgVdcNetwork.EdgeGateway.name
			}#endelse rename
			
			#check if user only wants to reapply service configuration
			if ($gwservices) {
				setVcdEdgeGatewayServiceConfiguration -vcdconnect $myvarTargetVcdConnect -EdgeGatewayXML $myvarEdgeGatewayXML
			}#endif gwservices
			else { #user wants to create the object
				#create the object on target if it does not laready exist
				if (!(getVcdObject -name $myvarNewEdgeGatewayName -type EdgeGateway -vcdConnect $myvarTargetVcdConnect)) {
					#EGW does not exist on target, so we need to create it
					createVcdEdgeGateway -vcdconnect $myvarTargetVcdConnect -EdgeGatewayXML $myvarEdgeGatewayXML
					Do {
						OutputLogData -category "INFO" -message "Waiting for the EdgeGateway $objectName to be created and ready..."
						Start-Sleep -Seconds 5
					} While ((Search-Cloud -QueryType EdgeGateway -Server $myvarTargetVcdConnect.Name -Name $objectName).GatewayStatus -ne "READY")
					Start-Sleep -Seconds 20
				}#end if EGW does not exist on target
				else {#EGW already exists on target
					OutputLogData -category "WARNING" -message "The Edge Gateway $myvarNewEdgeGatewayName already exists on $targetvcd : skipping creation."
				}#end else EGW already exists on target
			}#endelse gwservices
		}#endif EdgeGateway
		#endregion
		
		#region ExternalNetwork
		if ($objectType -eq "ExternalNetwork") {
			#retrieve the XML description for that object from the source
            $myvarExternalNetworkXML = getVcdObject -type ExternalNetwork -name $objectName -vcdConnect $myvarSourceVcdConnect
			#create the object on target if it does not laready exist
            if (!(getVcdObject -name $myvarExternalNetworkXML.VMWExternalNetwork.name -type ExternalNetwork -vcdConnect $myvarTargetVcdConnect)) {
				createVcdExternalNetwork -vcdConnect $myvarTargetVcdConnect -ExternalNetworkXML $myvarExternalNetworkXML
			}#end if External Network does not exist on target
			else {#External network already exists on target
				OutputLogData -category "WARNING" -message "The External Network $($myvarExternalNetworkXML.VMWExternalNetwork.name) already exists on $targetvcd : skipping creation."
			}#end else External Network already exists on target
		}#endif EdgeGateway
		#endregion
		
	}#endif else import	
	#endregion
	
	#region Cleanup
	if ($myvarSourceVcdConnect) {
		OutputLogData -category "INFO" -message "Disconnecting from the source vCloud Director instance $sourcevcd..."
		Disconnect-CIServer -Server $sourcevcd -Confirm:$false
	}#endif sourcevcdconnect
	
	if ($myvarTargetVcdConnect) {
		OutputLogData -category "INFO" -message "Disconnecting from the target vCloud Director instance $targetvcd..."
		Disconnect-CIServer -Server $targetvcd -Confirm:$false
	}#endif targetvcdconnect
	
	#let's figure out how much time this all took
	OutputLogData -category "SUM" -message "total processing time: $($myvarElapsedTime.Elapsed.ToString())"
	
	#cleanup after ourselves and delete all custom variables
	Remove-Variable myvar* -ErrorAction SilentlyContinue
	Remove-Variable help -ErrorAction SilentlyContinue
    Remove-Variable history -ErrorAction SilentlyContinue
    Remove-Variable log -ErrorAction SilentlyContinue
    Remove-Variable debugme -ErrorAction SilentlyContinue
    Remove-Variable sourcevcd -ErrorAction SilentlyContinue
	Remove-Variable targetvcd -ErrorAction SilentlyContinue
	Remove-Variable import -ErrorAction SilentlyContinue
	Remove-Variable objectType -ErrorAction SilentlyContinue
	Remove-Variable objectName -ErrorAction SilentlyContinue
	Remove-Variable gwservices -ErrorAction SilentlyContinue
	Remove-Variable userPassword -ErrorAction SilentlyContinue
	Remove-Variable rename -ErrorAction SilentlyContinue
    Remove-Variable NewOrgName -ErrorAction SilentlyContinue
    Remove-Variable NewOrgVdcName -ErrorAction SilentlyContinue
    Remove-Variable NewEdgeName -ErrorAction SilentlyContinue
    Remove-Variable pvDC -ErrorAction SilentlyContinue
	$ErrorActionPreference = "Continue"
	#endregion
	
#endregion