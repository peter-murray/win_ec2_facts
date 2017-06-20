#!powershell
#
# WANT_JSON
# POWERSHELL_COMMON

$ec2metadataUrl = "http://169.254.169.254/latest/meta-data/"
$ec2UserdataUrl = "http://169.254.169.254/latest/user-data/"
$prefix = "ansible_ec2_"

$AWS_REGIONS = ('ap-northeast-1',
                'ap-southeast-1',
                'ap-southeast-2',
                'eu-central-1',
                'eu-west-1',
                'eu-west-2',
                'sa-east-1',
                'us-east-1',
                'us-west-1',
                'us-west-2',
                'us-gov-west-1')

$selfData = @{}

Function Fetch-Content($uri)
{
    Try
    {
        $r = Invoke-WebRequest -Uri $uri -Method GET
        If ($r.StatusCode -ne 200)
        {
            Fail-Json (New-Object psobject) "Unexpected status code: $status for $uri"
            #$content = $null
            #$content = $r.Content

        }
        return $r.Content
    }
    Catch
    {
        return $null
    }
}

Function Fetch($uri, $recurse)
{
    $rawSubfields = Fetch-Content($uri)
    If ($rawSubfields -eq $null)
    {
        return $null
    }

    $subfields = $rawSubfields.Split()
    #Fail ($subfields) #TODO
    $subfields | foreach {
        $field = $_

        If ($field.EndsWith("/") -And $recurse)
        {
            Fetch -uri "$uri$field" -recurse $recurse
        }

        If ($uri.EndsWith("/"))
        {
            $newUri = "$uri$field"
        }
        Else
        {
            $newUri = "$uri/$field"
        }

        If (-Not $selfData.ContainsKey($newUri) -And -Not $newUri.EndsWith("/"))
        {
            $content = Fetch-Content($newUri)
            #TODO iam_info, iam_security_credentials and public_keys, are arrays here, will need to be specially catered for

            If ($field -eq "security_groups")
            {
                $selfData.Add([string]::Join(",", $content.Split()))
            }
            Else
            {
                $selfData.Add($newUri, $content)
            }
        }
    }
}

Function Get-Varname($var)
{
    $result = $var.Replace("/", "_")
    $result = $result.Replace("-", "_")
    $result = $result.Replace(":", "_")

    return "$prefix$result"
}

Function Mangle-Fields($toProcess, $uri)
{
    $allFields = @{}

    $toProcess.GetEnumerator() | ForEach {
        $field = $_.Key.Substring($uri.length)
        $value = $_.Value

        $key = Get-VarName($field)

        $allFields.Add($key, $value)
    }

    return $allFields
}

Function Add-Ec2-Region($myData)
{
    $zone = $myData["ansible_ec2_placement_availability_zone"]

    If ( $zone -ne $null)
    {
        $region = $zone
        ForEach($r in $AWS_REGIONS) {
            If ($zone.StartsWith($r))
            {
                $region = $r
                break
            }
        }

        $myData.Add("ansible_ec2_placement_region", $region)
    }
}


Function Run
{
    Fetch -uri $ec2metadataUrl -recurse $True
    $myData = Mangle-Fields $selfData -uri $ec2metadataUrl

    #Fetch -uri $ec2UserdataUrl -recurse $True
    #$myData = Mangle-Fields $selfData -uri $ec2UserdataUrl

    Add-Ec2-Region($myData)

    return $myData
}

$ec2Facts = Run

$result = New-Object psobject @{
    changed = $FALSE
    ansible_facts = $ec2Facts
};

$result.changed = $TRUE
Exit-Json $result
