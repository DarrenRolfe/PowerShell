<#*************************************************************************************************************************#>

 $AUTHOR   = "Darren Rolfe <darren.rolfe@rolfetechnical.uk>"
 $DATE     = "20 MAR 2018"
 $VERSION  = "6"
 $FILENAME = (Split-Path $MyInvocation.MyCommand.Definition -Leaf).TrimEnd(".ps1")

<#*************************************************************************************************************************

  DESC     = Account Management of Active Directory users within specific OUs

             Admin (OU=1) & User (OU>1) Accounts disabled after determined number of days
             User Accounts deleted after determined number of days
             Discovery of new accounts created within the last 7 days
            
             Group membership checks for addition/removal of users within sensitive groups

             Email reports to primary email ($ETS) and optionally secondary email ($ETC) accounts
             Email attachment with CSS formatted HTML for good readability
             Email attachment of WSUS script output is present
            
             Check for unused workstations/laptops with movement of object into dormant OU
            
  *************************************************************************************************************************#>

#############################################################################################################################
#                                                                                                                           #
### Variables                                                                                                               #
#                                                                                                                           #
# Environment Preferences                                                                                                   #
$VerbosePreference = "SilentlyContinue"
$ConfirmPreference = "None"
#                                                                                                                           #
# Set $SMT to SMTP server                                                                                                   #
$SMT = "smtp.domain.ext"
#                                                                                                                           #
# Mail Account credentials                                                                                                  #
$SecPWD = ConvertTo-SecureString "vTbG8JkwP98JnfSTb61Q" -AsPlainText -Force
$MSC = New-Object System.Management.Automation.PSCredential("it@domain.ext", $SecPWD)
#                                                                                                                           #
# Email From                                                                                                                #
$MFR = "IT Operations <it@domain.ext>"
#                                                                                                                           #
# Set email To target for report                                                                                            #
$ETS = "Administrators <administrators@domain.ext>"
#                                                                                                                           #
# Set email Cc targets for report                                                                                           #
$ETC = @("Technical Design Office <TDO-Mailbox@domain.ext>","Compliance Office <Compliance-Mailbox@domain.ext>")            
#                                                                                                                           #
# Set output filenames                                                                                                      #
$root = "\\server02.domain.ext\PowerShell"
$OUT = "$root\ADDS\{0:yyyyMMdd}-AD-AccountManagement.html" -f [DateTime]::now                                                   
$XMLFile = "$root\ADDS\AD-Groups.xml"
#                                                                                                                           #
# WSUS Statistics File                                                                                                      #
$WSUS = "$root\WSUS\{0:yyyyMMdd}-WSUS-Compliance-Statistics.html" -f [DateTime]::now
#                                                                                                                           #
# Set number of days until unused accounts are disabled                                                                     #
$NOD = 90
#                                                                                                                           #
# Set number of days until disabled are deleted                                                                             #
$NUD = $NOD+500
#                                                                                                                           #
# Set number of days to report new accounts                                                                                 #
$NEW = 7
#                                                                                                                           #
# Set search locations using the OU DistinguishedName and report headers                                                    #
#        Distinguished Name                                           HTML OU Header                                        #
$OUDN = @{                                                                                                                  #
    1 = "OU=Admin,CN=Users,DC=server,DC=local",                      "<h2>ADMIN USER ACCOUNTS</h2>"
    2 = "OU=Accounts,CN=Users,DC=server,DC=local",                   "<br /><h2>ACCOUNTS USER ACCOUNTS</h2>"
}                                                                                                                           #
#                                                                                                                           #
# Set AD groups to monitor membership                                                                                       #
#        Group without Spaces    Actual Group Name                                                                          #
$GRPS = @{                                                                                                                  #
    1 = "Administrators",       "Administrators"
    2 = "DomainAdministrators", "Domain Administrators"
    3 = "DomainAdmins",         "Domain Admins"
    4 = "EnterpriseAdmins",     "Enterprise Admins"
    5 = "ITOperations",         "IT Operations"
}                                                                                                                           #
#                                                                                                                           #
# Set OUs to check for dormant workstations                                                                                 #
#        Distinguished Name - Single level scope                     Human Friendly Name                                    #
$DORMANT = @{                                                                                                               #
    1 = "OU=Computers,OU=Computers,DC=server,DC=local",             "Computers"
    2 = "OU=Desktops,OU=Computers,DC=server,DC=local",              "Desktops"
    3 = "OU=Laptops,OU=Computers,DC=server,DC=local",               "Laptops"
}                                                                                                                           #
#                                                                                                                           #
#############################################################################################################################

### Code

# Manipulate each array, Moves array of AD objects into dormant OU
function ReportComputers ($adarray, $adtitle) {
    if ($OUTE) { Clear-Variable OUTE }
    if ($adovar) { Remove-Variable adovar }
    ForEach($adobject in $adarray) {
        $CNT++
        if($CNT % 2 -eq 0) {
            [string]$adovar += "<tr><td class='row1'><li>" + $adobject.Name + "</li></td><td class='row1'>" + $adobject.Description + "</td></tr>"
        } else {
            [string]$adovar += "<tr><td class='row2'><li>" + $adobject.Name + "</li></td><td class='row2'>" + $adobject.Description + "</td></tr>"
        }
    }
    if ($adovar) {
        $adotitle = $adtitle.Substring(0,$adtitle.Length-1)
        $OUTE += "<h3>$adtitle</h3><table><tr><th>$adotitle</th><th>Description</th></tr>$adovar</table>"
        ForEach ($adobject in $adarray) { 
            if(!(Test-Connection $adobject.Name -Count 1 -ErrorAction SilentlyContinue)) {
                #Set-ADComputer -Identity $adobject.Name -Enabled $false                                                                        ###################################
                #Get-ADComputer $adobject.Name | Move-ADObject -TargetPath 'OU=Dormant Computers,OU=Dormancy Process,OU=MyBusiness,DC=server,DC=local'  ############################
            }
        }
    } else {
        $OUTE += "<h3>No Redundant $adtitle</h3>"
    }
    return $OUTE
}

### Active Directory Account Check

# Set $DOM to domain name
$DOM = $env:USERDOMAIN

# Set $SVR to the current servername
$SVR = $env:COMPUTERNAME

# Date formatted in YYYYMMDD    
$GDF = Get-Date -format "yyyyMMdd"

# Set Email Subject
$EMS = "$GDF-$DOM Active Directory Compliance Check"

#Create output arrays for the logging
$OUTA = @()
$OUTB = @()

# Create output file
Out-File $OUT -Encoding Unicode

# Loop through OUDNs 1 to however many
For($DNE = 1; $DNE -le $OUDN.Count; $DNE++) {

    # Pull DN and header from array
    $DN = $OUDN[$DNE][0]
    $OUTA += $OUDN[$DNE][1]

    # Set loop counter
    $LPC = 0

    # Start loop to repeat searches
    Do {
    
        # Increment loop counter
        $LPC++

        # If loop 1 (accounts over NOD days)
        if ($LPC -eq 1) {

            # Work out NOD days ago
            $DAT = (get-date).adddays(-$NOD)

            # Get AD users where user has not logged on and date of last logon is over NOD days and the password has not been set within NOD days
            $USRS = (Get-ADUser -SearchBase $DN -filter {(lastlogondate -notlike '*' -OR lastlogondate -le $DAT) -AND (whencreated -le $DAT) -AND (passwordlastset -le $DAT) -AND (enabled -eq $True)} -Properties lastlogondate, passwordlastset, description, samaccountname, accountexpirationdate, whencreated | Select-Object name, lastlogondate, passwordlastset, description, samaccountname, accountexpirationdate, whencreated)
        }

        # If loop 2 (accounts disabled over NUD days)
        if ($LPC -eq 2) {

            # Work out NUD days ago
            $DAT = (get-date).adddays(-$NUD)

            # Get AD users where user account has been created within the last NEW days
            $USRS = (Get-ADUser -SearchBase $DN -filter {(lastlogondate -notlike '*' -OR lastlogondate -le $DAT) -AND (whencreated -le $DAT) -AND (passwordlastset -le $DAT) -AND (enabled -eq $False)} -Properties lastlogondate, passwordlastset, description, samaccountname, accountexpirationdate, whencreated | Select-Object name, lastlogondate, passwordlastset, description, samaccountname, accountexpirationdate, whencreated)
        }

        # If loop 3 (accounts newer than NEW days)
        if ($LPC -eq 3) {

            # Work out NEW days ago
            $DAT = (get-date).adddays(-$NEW)

            # Get AD users where user account has been created within the last NEW days
            $USRS = (Get-ADUser -SearchBase $DN -filter {(whencreated -gt $DAT) -AND (enabled -eq $True)} -Properties lastlogondate, passwordlastset, description, samaccountname, accountexpirationdate, whencreated | Select-Object name, lastlogondate, passwordlastset, description, samaccountname, accountexpirationdate, whencreated)
        }
    
        # Run USR loop
        ForEach($USR in $USRS) {
        
            # If loop 1 (accounts over NOD days)
            if ($LPC -eq 1) {

                # Set User Description
                $DES = $USR.description + " (Disabled: " + ((get-date).toshortdatestring()) + ")"
                #Set-ADUser $USR.samaccountname -Description $DES                                                                               ###################################

                # Disable user object
                #Disable-ADAccount $USR.samaccountname                                                                                          ###################################
                Write-Verbose "Disabled user: $USR.samaccountname"
            }

            if ($LPC -eq 2) {

                # Delete user object
                #Remove-ADUser $USR.samaccountname                                                                                              ###################################
                Write-Verbose "Remove user: $USR.samaccountname"
            }

            # Assign Get-ADUser results to variables
            $USR_SAM = $USR.samaccountname
            $USR_LLD = $USR.lastlogondate
            $USR_AED = $USR.accountexpirationdate
            $USR_NAM = $USR.name
            $USR_DES = $USR.description
            $USR_WCR = $USR.whencreated
            $CNT++

            # Check logon date for null value
            if (!$USR_LLD) { $USR_LLD = "No User Logon Ever!" }

            # Check expiry date for null value
            if (!$USR_AED) { $USR_AED = "No Expiry Date Set!" }

            # Check description for null value
            if (!$USR_DES) { $USR_DES = "No Description Set!" }

            # Add object to the log array  
            if ($LPC -lt 3) {
                if($CNT % 2 -eq 0) {
                    $PEND += "<tr><td class='row1'>$USR_WCR</td><td class='row1'>$USR_LLD</td><td class='row1'>$USR_SAM</td><td class='row1'>$USR_NAM</td><td class='row1'>$USR_DES</td></tr>"
                } else {
                    $PEND += "<tr><td class='row2'>$USR_WCR</td><td class='row2'>$USR_LLD</td><td class='row2'>$USR_SAM</td><td class='row2'>$USR_NAM</td><td class='row2'>$USR_DES</td></tr>"
                }
            }
            if ($LPC -eq 3) {
                if($CNT % 2 -eq 0) {
                    $PEND += "<tr><td class='row1'>$USR_WCR</td><td class='row1'>$USR_AED</td><td class='row1'>$USR_SAM</td><td class='row1'>$USR_NAM</td><td class='row1'>$USR_DES</td></tr>"
                } else {
                    $PEND += "<tr><td class='row2'>$USR_WCR</td><td class='row2'>$USR_AED</td><td class='row2'>$USR_SAM</td><td class='row2'>$USR_NAM</td><td class='row2'>$USR_DES</td></tr>"
                }
            }
        }

        # Results found, build table
        Write-Verbose "PEND: '$PEND'"

        # If loop 1 (accounts over NOD days)
        if ($LPC -eq 1) {

            if ($PEND) {

                # Open table and write headers in log array
                $OUTA += "<h3>Accounts Not Used for $NOD days (Since $DAT) - NOW DISABLED!</h3>"
                $OUTA += "<table><tr><th>Created On</th><th>Last Log On</th><th>SAM Account</th><th>Username</th><th>Description</th></tr>"
                
                # Include results
                $OUTA += $PEND
                Remove-Variable PEND
                Write-Verbose "PEND Write"

                # Close table within log array
                $OUTA += "</table>"

            } else {
                $OUTA += "<h3>No accounts idle for over $NOD days (Since $DAT)</h3>"
            }
        }

        # If loop 2 (accounts disabled over NUD days)
        if ($LPC -eq 2) {

            if ($PEND) {

                # Open table and write headers in log array
                $OUTA += "<h3>Accounts Not Used for $NUD days (Since $DAT) - NOW DELETED!</h3>"
                $OUTA += "<table><tr><th>Created On</th><th>Last Log On</th><th>SAM Account</th><th>Username</th><th>Description</th></tr>"
                
                # Include results
                $OUTA += $PEND
                Remove-Variable PEND
                Write-Verbose "PEND Write"

                # Close table within log array
                $OUTA += "</table>"

            } else {
                $OUTA += "<h3>No disabled accounts pending deletion over $NUD days (Since $DAT)</h3>"
            }
        }

        # If loop 3 (accounts newer than NEW days)
        if ($LPC -eq 3) {

            if ($PEND) {
                # Open table and write headers in log array
                $OUTA += "<h3>Accounts created in the last $NEW days (Since $DAT)</h3>"
                $OUTA += "<table><tr><th>Created On</th><th>Account Expires</th><th>SAM Account</th><th>Username</th><th>Description</th></tr>"

                # Include results
                $OUTA += $PEND
                Remove-Variable PEND
                Write-Verbose "PEND Write"

                # Close table within log array
                $OUTA += "</table>"

            } else {
                $OUTA += "<h3>No accounts created in the last $NEW days (Since $DAT)</h3>"
            }
        }

        # Skip erasure loop for admin accounts
        if (($DN -eq $OUDN[1]) -AND ($LPC -eq 1)) { $LPC++ }

    # Complete loop for correct number of reports
    } While ($LPC -le 3)
}

### Active Directory Group Membership Check

# Test for existing XML file, create framework if not found
if(Test-Path $XMLFile) {
    [xml]$GRPXml = Get-Content $XMLFile
} else {
    $GRPXml = [xml]"<MonitoredGroups/>"
    ForEach($GRP in $GRPS) {
        $XMLName = $GRP[0]
        $XMLNode = $GRPXml.CreateElement("$XMLName")
        $GRPXml.DocumentElement.AppendChild($XMLNode) | Out-Null
    }
}

# Execute for each Active Directory group
For($GRP = 1; $GRP -le $GRPS.Count; $GRP++) {

    # Pull AD Group name from array
    $GRPName = $GRPS[$GRP][1]
    $XMLName = $GRPS[$GRP][0]

    # Populate list of XML users
    $SrchXml = Select-Xml "//MonitoredGroups/$XMLName/USR/SAM" $GRPXml
    $XmlUSRS = % {$SrchXml.Node.'#text'}
            
    # Get AD users where user account has been created within the last NEW days
    $GRPMembers = Get-ADGroupMember -Identity "$GRPName" | Select-Object "SamAccountName", "distinguishedName"
    $USRS = @()
    ForEach ($USR in $GRPMembers) {
        $USER = $USR.SamAccountName
        $USR_DNR = $USR.distinguishedName.SubString($USR.distinguishedName.IndexOf(",")+1)
        Write-Verbose "Get-ADUser: $USER"
        $USR = (Get-ADUser -SearchBase $USR_DNR -Filter "((samaccountname -like '$USER') -AND (enabled -eq `$True))" `
            -Properties lastlogondate, passwordlastset, description, samaccountname, accountexpirationdate, whencreated | 
            Select-Object   @{Name="User Name";Expression={$_.name}},
                            @{Name="Last Logon Date";Expression={$_.lastlogondate}},
                            @{Name="Password Last Set";Expression={$_.passwordlastset}},
                            @{Name="Description";Expression={$_.description}},
                            @{Name="SAM Account Name";Expression={$_.samaccountname}},
                            @{Name="Expiry Date";Expression={$_.accountexpirationdate}},
                            @{Name="Creation Date";Expression={$_.whencreated}})
        if($USR."SAM Account Name") {

            # Assign Get-ADUser results to variables
            $USR_SAM = $USR."SAM Account Name"
            $USR_LLD = $USR."Last Logon Date"
            $USR_AED = $USR."Expiry Date"
            $USR_NAM = $USR."User Name"
            $USR_DES = $USR."Description"
            $USR_WCR = $USR."Creation Date"

            # Compare XML to array result and notify if previously not listed
            if ($XmlUSRS -notcontains $USR_SAM) {

                Write-Verbose "XML does not contain $USR_SAM"

                # Check logon date for null value
                if (!$USR_LLD) { $USR_LLD = "No User Logon Ever!" }

                # Check expiry date for null value
                if (!$USR_AED) { $USR_AED = "No Expiry Date Set!" }

                # Check description for null value
                if ($USR_DES.length -lt 2) { $USR_DES = "No Description Set!" }

                # Select XML location and make entry
                $XMLTarget = Select-Xml -Xml  $GRPXml -XPath "MonitoredGroups/$XMLName"
                $XMLNode = $GRPXml.CreateElement("USR")
                    
                $XMLNodes = $GRPXml.CreateElement("SAM")
                $XMLTexts = $GRPXml.CreateTextNode("$USR_SAM")
                $XMLNodes.AppendChild($XMLTexts) | Out-Null
                $XMLNode.AppendChild($XMLNodes) | Out-Null
                    
                $XMLNodes = $GRPXml.CreateElement("NAM")
                $XMLTexts = $GRPXml.CreateTextNode("$USR_NAM")
                $XMLNodes.AppendChild($XMLTexts) | Out-Null
                $XMLNode.AppendChild($XMLNodes) | Out-Null

                $XMLNodes = $GRPXml.CreateElement("LLD")
                $XMLTexts = $GRPXml.CreateTextNode("$USR_LLD")
                $XMLNodes.AppendChild($XMLTexts) | Out-Null
                $XMLNode.AppendChild($XMLNodes) | Out-Null

                $XMLNodes = $GRPXml.CreateElement("AED")
                $XMLTexts = $GRPXml.CreateTextNode("$USR_AED")
                $XMLNodes.AppendChild($XMLTexts) | Out-Null
                $XMLNode.AppendChild($XMLNodes) | Out-Null

                $XMLNodes = $GRPXml.CreateElement("DES")
                $XMLTexts = $GRPXml.CreateTextNode("$USR_DES")
                $XMLNodes.AppendChild($XMLTexts) | Out-Null
                $XMLNode.AppendChild($XMLNodes) | Out-Null

                $XMLNodes = $GRPXml.CreateElement("WCR")
                $XMLTexts = $GRPXml.CreateTextNode("$USR_WCR")
                $XMLNodes.AppendChild($XMLTexts) | Out-Null
                $XMLNode.AppendChild($XMLNodes) | Out-Null

                $XMLNodes = $GRPXml.CreateElement("DNR")
                $XMLTexts = $GRPXml.CreateTextNode("$USR_DNR")
                $XMLNodes.AppendChild($XMLTexts) | Out-Null
                $XMLNode.AppendChild($XMLNodes) | Out-Null

                $XMLTarget.Node.AppendChild($XMLNode) | Out-Null
                
                # Add object to the log array
                $PEND += "<tr><td>$USR_WCR</td><td>$USR_LLD</td><td>$USR_AED</td><td>$USR_SAM</td><td>$USR_NAM</td><td>$USR_DES</td></tr>"
                Write-Verbose "Embedded PEND: '$PEND'"
            }
            $USRS += $USR_SAM
        }
        Clear-Variable USR_DNR
    }

    # Results found, build table
    Write-Verbose "PEND: '$PEND'"
    if ($PEND) {

        # Open table and write headers in log array
        $OUTB += "<br /><h3>New accounts in the $GRPName group</h3>"
        $OUTB += "<table><tr><th>Created On</th><th>Last Logon Date</th><th>Account Expiry Date</th><th>SAM Account</th><th>Username</th><th class='desc'>Description</th></tr>"

        # Include results
        $OUTB += $PEND
        Remove-Variable PEND
        Write-Verbose "PEND Write for $GRPName (ADDED)"

        # Close table within log array
        $OUTB += "</table>"
    }

    # Save additions to file
    $GRPXml.Save($XMLFile)

    # Compare XML to array result and notify if removed
    $GrpUSRS = ($GRPXml.SelectNodes("MonitoredGroups/$XMLName") | select -ExpandProperty childnodes).SAM
    ForEach ($USR in $GrpUSRS) {
        if ($USRS -notcontains $USR) {

            # Get results from AD and include
            $XMLTarget = Select-Xml -Xml  $GRPXml -XPath "MonitoredGroups/$XMLName/USR"
            ForEach ($XMLNode in $XMLTarget) {
                $XMLNodes = $XMLNode.Node.SAM
                if ($USR -like $XMLNodes) {
                    $XMLSrch = $XMLNode
                    $USR_DNR = $XMLNode.Node.DNR
                }
            }
            Remove-Variable ADUSR                                
            $ADUSR = (Get-ADUser -SearchBase $USR_DNR -Filter "(samaccountname -like '$USR')" `
                -Properties lastlogondate, passwordlastset, description, samaccountname, accountexpirationdate, whencreated | 
                Select-Object   @{Name="User Name";Expression={$_.name}},
                                @{Name="Last Logon Date";Expression={$_.lastlogondate}},
                                @{Name="Password Last Set";Expression={$_.passwordlastset}},
                                @{Name="Description";Expression={$_.description}},
                                @{Name="SAM Account Name";Expression={$_.samaccountname}},
                                @{Name="Expiry Date";Expression={$_.accountexpirationdate}},
                                @{Name="Creation Date";Expression={$_.whencreated}})
            Write-Verbose "AD group $XMLName does not contain $USR"

            # User found in AD
            if($ADUSR."SAM Account Name") {

                # Assign Get-ADUser results to variables
                $USR_SAM = $ADUSR."SAM Account Name"
                $USR_LLD = $ADUSR."Last Logon Date"
                $USR_AED = $ADUSR."Expiry Date"
                $USR_NAM = $ADUSR."User Name"
                $USR_DES = $ADUSR."Description"
                $USR_WCR = $ADUSR."Creation Date"

                # Check logon date for null value
                if (!$USR_LLD) { $USR_LLD = "No User Logon Ever!" }

                # Check expiry date for null value
                if (!$USR_AED) { $USR_AED = "No Expiry Date Set!" }

                # Check description for null value
                if ($USR_DES.length -lt 2) { $USR_DES = "No Description Set!" }
              
            # Pull details from XML as AD failed
            } else {
                $USR_SAM = $XMLSrch.Node.SAM
                $USR_LLD = $XMLSrch.Node.LLD
                $USR_AED = $XMLSrch.Node.AED
                $USR_NAM = $XMLSrch.Node.NAM
                $USR_DES = $XMLSrch.Node.DES
                $USR_WCR = $XMLSrch.Node.WCR
            }

            # Remove entry and create HTML row
            $XMLSrch.Node.ParentNode.RemoveChild($XMLSrch.Node) | Out-Null
            $PEND += "<tr><td>$USR_WCR</td><td>$USR_LLD</td><td>$USR_AED</td><td>$USR_SAM</td><td>$USR_NAM</td><td>$USR_DES</td></tr>"
        }
    }

    # Results found, build table
    Write-Verbose "PEND: '$PEND'"
    if ($PEND) {

        # Open table and write headers in log array
        $OUTB += "<br /><h3>Accounts removed from the $GRPName group</h3>"
        $OUTB += "<table><tr><th>Created On</th><th>Last Logon Date</th><th>Account Expiry Date</th><th>SAM Account</th><th>Username</th><th class='desc'>Description</th></tr>"

        # Include results
        $OUTB += $PEND
        Remove-Variable PEND
        Write-Verbose "PEND Write for $GRPName (REMOVED)"

        # Close table within log array
        $OUTB += "</table>"
    }

    # Remove deletions from file
    $GRPXml.Save($XMLFile)
}

# Output compiled results to HTML document
Write-Verbose "OUTB: '$OUTB'"
if (!$OUTB) { $OUTB = "<br /><h3>No irregularities have been detected in any of the monitored groups.</h3>" }

### Unused Workstations Check

# The 60 is the number of days from today since the last logon.
$then = (Get-Date).AddDays(-60)

# Call the move AD objects function and create HTML output
$OUTD = "<hr /><br /><h1>Redundant Systems</h1>"

# Loop through dormant OUs
For($DORM = 1; $DORM -le $DORMANT.Count; $DORM++) {

    # Split dorm contents
    $DORMOU = $DORMANT[$DORM][0]
    $DORMName = $DORMANT[$DORM][1]

    # Return OU objects
    $adobjects = Get-ADComputer -Property Name,Description,lastLogonDate -Filter {lastLogonDate -lt $then} -SearchBase "$DORMOU" -SearchScope OneLevel | Select-Object Name, Description
    $OUTD += ReportComputers $adobjects $DORMName
}

### Email / Closure of Script

# Create Email
$Head = "<title>Active Directory Compliance Check</title><link href='https://fonts.googleapis.com/css?family=Jura:500|Walter+Turncoat' rel='stylesheet'>"
$Head += "<style>
            body {
                font-family: Calibri, Arial;
                font-size: 12pt;
                color: #333;
                background-color: #ccc;
                margin: 10px;
            }
            th {
                font-weight: bold;
                font-size: 16px;
                color: white;
                background-color: #333;
                width: 140px;
                padding: 5px;
            }
            table {
                border: 1px #000000 solid;
                border-collapse: collapse;
                padding-bottom: 30px;
                width: 800px;
            }
            .desc {
                width: 340px;
            }
            .date {
                font-size: 14pt;
                font-weight: bold;
                padding-left: 600px;
            }
            h1 {
                font-size: 26pt;
                font-weight: bold;
                padding: 0px;
                padding-left: 100px;
                margin-bottom: -10px;
            }
            h1.bighead {
                font-family: Segoe, Tahoma, Arial, Helvetica;
            }
            h2 {
                font-family: 'Walter Turncoat', cursive, Arial;
                font-size: 16pt;
                padding-left: 50px;
                padding-bottom: 0px;
                padding-top: 0px;
            }
            h3 {
                font-size: 12pt;
                font-decoration: underline;
            }
            hr {
                width: 800px;
                height: 3px;
                text-align: left;
                color: #333;
            }
            div.tail {
                font-family: 'Jura', sans-serif;
                font-size: 12px;
                font-decoration: italic;
                padding-left: 50px;
            }
            td {
                border: 1px solid #000;
                font-size: 14px;
                padding: 2px;
            }
            td.row1 {
                background-color: #eee;
            }
            td.row2 {
                background-color: #ddd;
            }
          </style>"
$TODAY = Get-Date -Format D
$FRAG1 = "Greetings!<br /><br />&nbsp;&nbsp;&nbsp;See below for results of the latest Active Directory Compliance Check. All accounts not used for $NOD days have been disabled.<br /><br />Please note: All dates are in the format MM/DD/YYYY.<br /><br /><hr /><h1>AD Account Monitoring</h1>"
$FRAG2 = $OUTA | Out-String
$FRAG3 = "<hr /><h1>AD Group Membership Monitoring</h1>"
$FRAG4 = $OUTB | Out-String
$FRAG5 = "<br /><hr /><br />Regards<br /><br />&nbsp;&nbsp;$SVR<br /><br /><br /><div class=''>$FILENAME | version: $VERSION | $DATE | $AUTHOR</div>"
$FRAG6 = $OUTD | Out-String
($OUTC = ConvertTo-Html -Head $Head -Body "<h1 class='bighead'>Active Directory Compliance Check</h1><p class='date'>Created $TODAY</p>",$FRAG1,$FRAG2,$FRAG3,$FRAG4,$FRAG6,$FRAG5) | Out-File $OUT

# Create New Email object
$MSG = New-Object Net.Mail.MailMessage
$MSG.Body = $OUTC
$MSG.IsBodyHtml = $true

# Pull WSUS statistics file
if(Test-Path $WSUS) {
    $ATT = @($OUT, $WSUS)
} else {
    $ATT = @($OUT)
}

# Send Email
Send-MailMessage -To $ETS -Subject $EMS -Body $MSG.Body -SmtpServer $SMT -From $MFR -BodyAsHtml -Attachments $ATT -Credential $MSC -Port 587 -Cc $ETC

# End 
