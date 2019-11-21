Import-Module Rubrik

# 9. List of permissions and roles/ for a specific server – who can backup/restore data of a specific server
# Script Flow ->
#     1. Get All User/Groups/Roles from Rubrik
#     2. Get the Object to check
#     3. Determine Users and Roles with permissions to this object (e.g. Specific Managed Authorization, Admin Roles, AD Group Membership)

$HTML_Check = "<p>&#9989;</p>"
$HTML_Cross = "<p>&#10060;</p>"

$output_folder = '.' #Use local path to output HTML Report To
$output_file_name = $output_folder + "\" + $(get-date -uFormat "%Y%m%d-%H%M%S") + "-PermissionsReport.html" #Name of HTML Report

$RubrikCDM = Read-Host -Prompt "Please Enter the Rubrik DNS or IP Address"
$RubrikCreds = Get-Credential
$RubrikObject = Read-Host -Prompt "Please enter the Rubrik Object to view Permissions"
$CDMConnection = Connect-Rubrik -Server $RubrikCDM -Credential $RubrikCreds

# Define HTML Output Report
$output_html = @()
$style_head = @"
<head><style>
P {font-family: Calibri, Helvetica, sans-serif;}
H1 {font-family: Calibri, Helvetica, sans-serif;}
H3 {font-family: Calibri, Helvetica, sans-serif;}
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; position: sticky; padding: 3px; border-style: solid; border-color: black; background-color: #00cccc; font-family: Calibri, Helvetica, sans-serif;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black; font-family: Calibri, Helvetica, sans-serif;}
</style></head>
"@
# Create HTML File contents, with Report Header and Table Headers
$output_html += $style_head
$output_html += "<hr>"
$output_html += '<IMG style="padding: 0 15px; float: left;" SRC="data:image/gif;base64,iVBORw0KGgoAAAANSUhEUgAAAXUAAAC0CAMAAABc4ExfAAAARVBMVEUlsaMlsKMlsZwnr7ckspImr7Aoq5QmsKo5kn9jZmtjZmtjZmtjZmtjZmtjZmtjZmtjZmtjZmsmr7YlsaUkspkkso8nrsJo0+JyAAAAEXRSTlOCn1/NxzgAEgEWPVuApL/V7xQTl6oAAAphSURBVHja7d3pdqowEABgFgmHQNisvv+jXnayTBZCkKtn5l9bxfYzDVlmYkQwPh8REqA6qmOgOqpjoDqqY6A6qmOgOqqjOgaqozoGqqM6BqqjOgaqozqqY6A6qmOgOqpjoDqqY6A6qmOcVM+zHOk+rZ68Xq8E7T6rPqIj+7XqSm8yoyvs2OuEU8/i1+sBosvsj7+/OEPQAOrZY+KF0SX2vzEe6H5WfTEX1Hn0v79EVkf3s+r5xqtDF9hn9Ofzid37GfVMVZfRefYV/YmN/VQPE8vqKjrHvqLHiHrubhqL6hD6zo7oocYwMa8Oo2/siB5svB7v6jr0lR3Rw82S4lVdj76w/3/oRVmNUXzuFecXpOdXBOJZ3YQ+s/9/LZ11U7SfQ59fsCtOq4/sNvSJ/f/rXmpXhFBRLS9Iz6uTKLKiv57J+LD/VJ1+o/oQDxv68/Ef3rO+Sj2LxEjyzIr+TIdeSHpejuru6vlLjohENvTn8JinHDmqO6tHivprmy5p0eN55ChGhOrn1Gd2EzqqX6A+shvRUf0KdRKb0VH9EnWInUNH9WvUVXYeXVXvf1m9ZE3Dyk+oy+wCuqLe/7B6sSzx1MUpdS6ZxaAusovoREHf1W9KlblOfUHvOnZGfZh8PnIHdZ5dQicK+qaep32f/ZI67bagJ9THdZaV3ai+s8voREFf1Uf0Pv4l9WpXr/zV50WAhd2svrIr6ERBX9Qn9L7Pf1O99ldf5vszu6r+RxR2FZ0o6LP6gn5HY/+EOvNW39a7JnZF/U9UH9kBdKKgT+or+h2N/TL1clcvvdW3vJeJPZLNZfXh8dAeqYI+qu/oNzT268YwzYreFr7q/NLuwB4p6LI6iaE9UgV9UOfQb2js16nTdkGn3iPHjFd+iF9O6GorTSK1ZiCWzMfRYip++TtzUzpdu6Yn5qbRY4/h6+QhRuzWSPM4FWN4YyLuy+iHephxekopDbcOk8SheoI8vrmI5ntWvxJulnoSfeheElR3UU+46dJ59JvZv0U94adLAdDvZf8S9USYLoVAv5X9O9QTYdweBv1O9q9QF9LqTrELk6P72L9BXcplPMEuot/H/gXqSgKpN7uM3r8TVIfVgaxdT3YV/e3BTqf8+5KGVS+Gy7KaDRd2z65eag9cnnFUHUyV9mKH0J3YaVUPMRc6lNuiXkOhn8tRsulnhVG9qJp9hbZrDCUV1Xg5Nl2uqNptKb2Af1mrejE9uOZSCiI9uhc7jO7C3m7bBAXjdLacf1PlRQvtHYvq4kU7aPFqI91356jwRu0PaYCdJJ160SibrJEB3YNdh+7Avm2JFY1gQyVD43O16lUHRV2Y1Wnbweod+MuA6tyfI6gbKjEOsuvR7ewbhIhekwDq0jX3aEuTuojO70y7q3MvXfM9jLH85RC7Cd3Kvv5qdQc29TPqVIcub/KL6kxEb4iHOofeFJy6peboALsZ3cYOozByXr1qu+4IO4UfWHqow+gkshZ6ObPb0C3s8h/ZSPVz/ur8Retx6NhqNWH1Rm7qruoadGGXVJMq7boJFNvQ329X9XYakw0jrpIEVK+3MTcVOg9qUm+mJ1HG6HF1HTqvrstPdy2vS63oruqsMMx5fNUbcWTBDWqaQq9emX9Zo7oWnUQPa6GX68QysqKnburMONP0VFf4uAFKpVUvyQl1pn1fo+xlL/Ty6GIg9HfmpN6QC9QBPq4pFhr1ipxQ16MPY5gsFDrPfhyd2NrXKXXwmkUL/3dROMfooLoBfc2HCYK+s3ugE0tTP6XOzFN/iZdanuakbkKf5qZZKPSV3Qed2P7UE+raNluB/wvU1qs7qBvR53WYLBT6zO6FTmx/6gl1bfe89TEMVC+81c3oa61GKPSR3Q+ddJbFaX91ffe8N3ZQnfiqW9DX9fUsFPrA7odObA3MX50Ztiyg95rCl3NXbyzo215SFgodZHdJLLU1MH/10vCqDdAJnVa3oe/7plkodIDdKZv3OvXCYdONXaGuQ+dyBLJQ6Aq7Wwr1ZeqN6VVL4KnUdhN2VNffT7ilrSwUusTumLduGa77q9fG3doL1fU3FH5BMQuFLrC7FgvY/q291dnRf7Fg6torCMu4WSh0jt25QuMy9eo+dd2NXFw8z0Khb+zuZTE/qa6ZfUhbFlm4E0jjY+jXqTv1681F6i11UCdZ/AhVQBS/0yMFYPeqh72bsso8kLmyRuvY2YKXqRtPjK2uUGcuq1+PdaA+n8sYS2eOOLbYTJ4bDZdOXTeSzqkX/rMkZpibeqtTYZkZXunNOPRnRBLlUCPFK49TtVIvBVICouPr6z7q1H9FoAUeE0Sd26lipra+3EjV0zCfMvq4L53K7OrqSySM20O1dXpYndm7dXD165S6kX2q8uXR7epL3ovMDqpz7Mlt6oYuhkEz4jDqhu3w+cwM4YNIbOpbspHEDqvv7Hkg9cptCYtXZ9aFXnaBOs9eAmOYiP9MDIs6l+ElsmvUV3brYMmmXukJGcxUd7bGzsDJTCh1/kQTqqrn/GdimNWFtDqBXae+sOeh1Bu3W6I4jDAvOEo/D6bOsYuzpWiTXmekqnqvQRfZteoTu31eYFPX7yGXmul3bVn923uA8iJ1opktLWdzPfZsxkg9mFGHLrDr1YcBZJqfVt9atDz+3QYLDdGqQ+w7ekOuUtfMloBTNNWDGbXob47ToB5kbqo7RHH/fmVQV3Mn9fe6kOqkgbo5q3q/q4Op0hv75eoFWNiizZtTsksFW75MqSYXqoPDdpt6v6tr8tNX9svVuf/Wbs1r5nIgVCQ5k3ovuyuZaaMtqDqX17ezW9T7XV1bFLCwX69e8Enn7VhM2Bq3hrd8GOlZtWUtNqw61JWZ1ftd3VCJMbNfry6VxFkXsrd1mMZUIVOSi9WBzGyjer+rG8tfJvYPqPPTDofdg20NoWgOPS+0ujpbMqn3u7ql5mhk/4S6trWDWzZc5SPToDeUfECdG7bP/aAqkyjoqb3Qa2BPjxV/+amTonav1uXX1+E6vMo4H7Ort47q3ECAwup5Kp+Gmdir6wb2BHgnjkTjkkdB+DMG4DGhgtAoQ0VT+RM3RDWsy8NJH6V+044JAyaoF8jEyF2q694xyaXnHdzvGw9IBM5IhNz5CrqW6Z8yX3E1EE9vqA2fwGn/VTSPEF8Q+NHyM6e+N7ejvz97HuxyfMiRE0dmrCrACSgBdpTt5GlKst5e6JWmt3/w3ddEZEcfxzCZvbrucEeO6kb0cbyeWavr3sgeSn0evZCdXV/+8kb2QOrLkJFs7Iaaozeyh1Ffx+lkZTcVer2RPYj6Njlax/HG6ro3sgdRT3tRHWTfJkOu2UYYRvWsl9UB9n0Gerg4A9Xd2rrKzgljWw/Ur0eKusTON+vFPMJ+/fR4PUkldYFd6Esm8wRFg6wIDO5S7ZKmA4/QPJw6cJfFu+YN6gs7on9WnWTpsUIvjBDqGKiO6hiojuoYqI7qqI6B6qiOgeqojoHqqI6B6qiO6hiojuoYqI7qGKiO6hiojuoYqI7qqI6B6qiOgeqojoHqqI6B6qiO6hiojuoYqP4z8Q92ktUsazqmOgAAAABJRU5ErkJggg==">'
$output_html += '<p style="margin-top: 20px;">'
$output_html += "<h1>Global Permission Report for Object: $($RubrikObject) </h1>"
$output_html += "<h3>Rubrik Cluster: $($global:rubrikConnection.server)</h3>"
$output_html += "<h3>Date/Time: $(Get-Date)</h3>"
$output_html += "</p>"
$output_html += "</br>"
$output_html += "<hr>"
$output_html += "<table>"
$output_html += "<th>#</th>"
$output_html += "<th>User ID</th>"
$output_html += "<th>Username</th>"
$output_html += "<th>User Domain/Local</th>"
$output_html += "<th>Read Only Permissions</th>"
$output_html += "<th>Full Admin Permissions</th>"
$output_html += "<th>Organisation viewLocalLdapSerice</th>"
$output_html += "<th>Organisation manageSla</th>"
$output_html += "<th>Organisation viewPrecannedReport</th>"
$output_html += "<th>Organisation manageSelf</th>"
$output_html += "<th>Organisation useSla</th>"
$output_html += "<th>Organisation manageResource</th>"
$output_html += "<th>Organisation viewOrg</th>"
$output_html += "<th>Organisation manageCluster</th>"
$output_html += "<th>Organisation createGlobal</th>"
$output_html += "<th>Managed Volume Admin</th>"
$output_html += "<th>Managed Volume User</th>"
$output_html += "<th>End User viewEvents</th>"
$output_html += "<th>End User restoreWithoutDownload</th>"
$output_html += "<th>End User destructiveRestore</th>"
$output_html += "<th>End User onDemandSnapshot</th>"
$output_html += "<th>End User viewReport</th>"
$output_html += "<th>End User restore</th>"
$output_html += "<th>End User provisionOnInfra</th>"


# Grab all Local and Remote LDAP/LOCAL Services
$RubrikLDAPServices = Invoke-RubrikRESTCall -Endpoint 'ldap_service' -Method GET -api 1

# Setup payload to get all principles (Users, Groups, Roles) inside Rubrik
$RubrikPrincipleSearchPayload = @{
    "limit" = 9999
    "offset" = 0
    "queries" = @()
    "sort" = @(@{
        "attr" = "displayName"
        "order" = "asc"
    })
}

# Loop through Auth Domains and add to Principles Queries
foreach($RubrikLDAPDomain in $RubrikLDAPServices.data){
    $newAuthDomain = @(@{
        "authDomainId" = $RubrikLDAPDomain.id
    })
    $RubrikPrincipleSearchPayload.queries += $newAuthDomain
}

# Setup Payload to Search for input Object
$RubrikSearchPayload = @{
    "searchText" = $RubrikObject
    "searchProperties" = @("name","location")
    "objectTypes" = @("VirtualMachine","VcdVapp","HypervVirtualMachine","NutanixVirtualMachine","ManagedVolume","MssqlStandaloneDatabase","MssqlAvailabilityDatabase","LinuxFileset","WindowsFileset","ShareFileset","LinuxHost","WindowsHost","NasHost","NfsHostShare","SmbHostShare","Ec2Instance","OracleDatabase","StorageArrayVolumeGroup")
    "offset" = 0
    "limit" = 9999
}

# Get all Users, Roles and Objects that can be used for permissions
$RubrikPrincipleSearch = Invoke-RubrikRESTCall -Endpoint 'principal_search' -Method POST -Body $RubrikPrincipleSearchPayload -api internal

# Find Objects in Rubrik matching search term inputted by User
$SearchObjects = Invoke-RubrikRESTCall -Endpoint 'hierarchy/search' -Method POST -Body $RubrikSearchPayload -api internal

$ldapCtr = 1

# Check we have objects
if($SearchObjects.data) {

    foreach($SearchObject in $SearchObjects.data){

        # Skip Relics
        if($SearchObject.isRelic -eq "True"){

            Write-Host 'Relic Found, Skipping...'

        } else {

            $ObjectPrompt = Read-Host -Prompt "Found Object Called $($SearchObject.name) which has the type: $($SearchObject.objectType) - is this the object you would like to check? (Y/N)"

            if($ObjectPrompt.ToLower() -eq 'y'){

               # Start Permission Check
               Write-Host "Checking Permissions on Object $($SearchObject.id)"

               foreach($AccountObject in $RubrikPrincipleSearch.data){

                    if(($AccountObject.principalType -eq 'group') -or ($AccountObject.isDeleted -eq 'True')){

                        # skip groups and deleted accounts - direct permissions will check groups

                    } else {

                        $AccountBody = @{
                            "principal" = $AccountObject.id
                            "resources" = @(
                                $SearchObject.id
                            )
                        }

                        $Permissions = Invoke-RubrikRESTCall -Endpoint 'authorization/effective/for_resources' -Method POST -Body $AccountBody -api internal
                        foreach($domain in $RubrikLDAPServices.data){
                            if($AccountObject.authDomainId -eq $domain.id) {
                                $userDomain = $domain.name
                            }
                        }

                        Write-Host "
Permissions for: $($AccountObject.name) @ $($userDomain)
----------------------------------------------------
Read Only Admin: $($Permissions.readOnlyAdmin.basic)
Full Admin: $($Permissions.admin.fullAdmin)
Org Admin: $($Permissions.organization)
Managed Volume Admin: $($Permissions.managedVolumeAdmin.basic)
Managed Volume User: $($Permissions.managedVolumeUser.basic)
End User: $($Permissions.endUser)
----------------------------------------------------
"

                        #Begin Formatting Permissions
                        if($Permissions.readOnlyAdmin.basic -ne $null){ $readOnly = $HTML_Check } else { $readOnly = $HTML_Cross }
                        if($Permissions.admin.fullAdmin -ne $null){ $fullAdmin = $HTML_Check } else { $fullAdmin = $HTML_Cross }
                        if($Permissions.organization.viewLocalLdapSerice -ne $null){ $viewLocalLdapSerice = $HTML_Check } else { $viewLocalLdapSerice = $HTML_Cross }
                        if($Permissions.organization.manageSla -ne $null){ $manageSla = $HTML_Check } else { $manageSla = $HTML_Cross }
                        if($Permissions.organization.viewPrecannedReport -ne $null){ $viewPrecannedReport = $HTML_Check } else { $viewPrecannedReport = $HTML_Cross }
                        if($Permissions.organization.manageSelf -ne $null){ $manageSelf = $HTML_Check } else { $manageSelf = $HTML_Cross }
                        if($Permissions.organization.useSla -ne $null){ $useSla = $HTML_Check } else { $useSla = $HTML_Cross }
                        if($Permissions.organization.manageResource -ne $null){ $manageResource = $HTML_Check } else { $manageResource = $HTML_Cross }
                        if($Permissions.organization.viewOrg -ne $null){ $viewOrg = $HTML_Check } else { $viewOrg = $HTML_Cross }
                        if($Permissions.organization.manageCluster -ne $null){ $manageCluster = $HTML_Check } else { $manageCluster = $HTML_Cross }
                        if($Permissions.organization.createGlobal -ne $null){ $createGlobal = $HTML_Check } else { $createGlobal = $HTML_Cross }
                        if($Permissions.managedVolumeAdmin.basic -ne $null){ $managedVolumeAdmin = $HTML_Check } else { $managedVolumeAdmin = $HTML_Cross }
                        if($Permissions.managedVolumeUser.basic -ne $null){ $managedVolumeUser = $HTML_Check } else { $managedVolumeUser = $HTML_Cross }
                        if($Permissions.endUser.viewEvent -ne $null){ $viewEvent = $HTML_Check } else { $viewEvent = $HTML_Cross }
                        if($Permissions.endUser.restoreWithoutDownload -ne $null){ $restoreWithoutDownload = $HTML_Check } else { $restoreWithoutDownload = $HTML_Cross }
                        if($Permissions.endUser.destructiveRestore -ne $null){ $destructiveRestore = $HTML_Check } else { $destructiveRestore = $HTML_Cross }
                        if($Permissions.endUser.onDemandSnapshot -ne $null){ $onDemandSnapshot = $HTML_Check } else { $onDemandSnapshot = $HTML_Cross }
                        if($Permissions.endUser.viewReport -ne $null){ $viewReport = $HTML_Check } else { $viewReport = $HTML_Cross }
                        if($Permissions.endUser.restore -ne $null){ $restore = $HTML_Check } else { $restore = $HTML_Cross }
                        if($Permissions.endUser.provisionOnInfra -ne $null){ $provisionOnInfra = $HTML_Check } else { $provisionOnInfra = $HTML_Cross }

                        if($Permissions.admin.fullAdmin -ne $null) {
                            $readOnly = $HTML_Check
                            $fullAdmin = $HTML_Check
                            $viewLocalLdapSerice = $HTML_Check
                            $manageSla = $HTML_Check
                            $viewPrecannedReport = $HTML_Check
                            $manageSelf = $HTML_Check
                            $useSla = $HTML_Check
                            $manageResource = $HTML_Check
                            $viewOrg = $HTML_Check
                            $manageCluster = $HTML_Check
                            $createGlobal = $HTML_Check
                            $managedVolumeAdmin = $HTML_Check
                            $managedVolumeUser = $HTML_Check
                            $viewEvent = $HTML_Check
                            $restoreWithoutDownload = $HTML_Check
                            $destructiveRestore = $HTML_Check
                            $onDemandSnapshot = $HTML_Check
                            $viewReport = $HTML_Check
                            $restore = $HTML_Check
                            $provisionOnInfra = $HTML_Check
                        }

                        $output_html += "<tr>"
                        $output_html += "<td>$($ldapCtr)</td>"
                        $output_html += "<td>$($AccountObject.id)</td>"
                        $output_html += "<td>$($AccountObject.name)</td>"
                        $output_html += "<td>$($userDomain)</td>"
                        $output_html += "<td>$($readOnly)</td>"
                        $output_html += "<td>$($fullAdmin)</td>"
                        $output_html += "<td>$($viewLocalLdapSerice)</td>"
                        $output_html += "<td>$($manageSla)</td>"
                        $output_html += "<td>$($viewPrecannedReport)</td>"
                        $output_html += "<td>$($manageSelf)</td>"
                        $output_html += "<td>$($useSla)</td>"
                        $output_html += "<td>$($manageResource)</td>"
                        $output_html += "<td>$($viewOrg)</td>"
                        $output_html += "<td>$($manageCluster)</td>"
                        $output_html += "<td>$($createGlobal)</td>"
                        $output_html += "<td>$($managedVolumeAdmin)</td>"
                        $output_html += "<td>$($managedVolumeUser)</td>"
                        $output_html += "<td>$($viewEvent)</td>"
                        $output_html += "<td>$($restoreWithoutDownload)</td>"
                        $output_html += "<td>$($destructiveRestore)</td>"
                        $output_html += "<td>$($onDemandSnapshot)</td>"
                        $output_html += "<td>$($viewReport)</td>"
                        $output_html += "<td>$($restore)</td>"
                        $output_html += "<td>$($provisionOnInfra)</td>"

                        $readOnly = $null
                        $fullAdmin = $null
                        $viewLocalLdapSerice = $null
                        $manageSla = $null
                        $viewPrecannedReport = $null
                        $manageSelf = $null
                        $useSla = $null
                        $manageResource = $null
                        $viewOrg = $null
                        $manageCluster = $null
                        $createGlobal = $null
                        $managedVolumeAdmin = $null
                        $managedVolumeUser = $null
                        $viewEvent = $null
                        $restoreWithoutDownload = $null
                        $destructiveRestore = $null
                        $onDemandSnapshot = $null
                        $viewReport = $null
                        $restore = $null
                        $provisionOnInfra = $null

                        $ldapCtr++

                    }
               }
            } else {
               Write-Host "Checking Next Object..."
            }
        }

    }

} else {
    Write-Output "No Objects found matching search term: $($RubrikObject)"
}

$output_html += "</table>"
$output_html > $output_file_name
