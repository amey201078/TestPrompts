<#
.SYNOPSIS
    Generates a Dynamics 365 CE solution folder structure, populates solution.xml, customizations.xml, [Content_Types].xml,
    and compresses the folder into a .zip file ready for import.

.DESCRIPTION
    - Reads the TDD for Customer Onboarding.
    - Creates the folder structure: SolutionRoot/{solution.xml, customizations.xml, [Content_Types].xml, WebResources/}
    - Writes the XML files based on TDD structure.
    - Uses Compress-Archive to package the solution for Dynamics import.
    - Handles errors gracefully and outputs key steps.

.NOTES
    - Customize the entity, attributes, and other XML as needed per your real TDD.
    - Requires PowerShell 5.0+ for Compress-Archive.
#>

param(
    [string]$SolutionName = "CustomerOnboarding",
    [string]$PublisherPrefix = "rb",
    [string]$Version = "1.0.0.0",
    [string]$RootPath = "$PSScriptRoot\D365CESolution"
)

function New-D365CESolutionFolderStructure {
    [CmdletBinding()]
    param (
        [string]$RootPath
    )
    try {
        if (Test-Path $RootPath) { Remove-Item $RootPath -Recurse -Force }
        New-Item -ItemType Directory -Path $RootPath | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $RootPath "WebResources") | Out-Null
        Write-Host "Created Dynamics 365 CE solution folder structure at $RootPath." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create folder structure: $_"
        exit 1
    }
}

function New-D365CESolutionXmlFiles {
    [CmdletBinding()]
    param (
        [string]$RootPath,
        [string]$SolutionName,
        [string]$PublisherPrefix,
        [string]$Version
    )

    try {
        # 1. solution.xml
        $solutionXml = @"
<?xml version="1.0"?>
<ImportExportXml xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" UniqueName="$SolutionName" LocalizedName="$SolutionName>
<SolutionManifest>
"@
        Set-Content -Path (Join-Path $RootPath "solution.xml") -Value $solutionXml 

        # 2. customizations.xml (SAMPLE)
        $customizationsXml = @"

  <Entities>
    <Entity Name="${PublisherPrefix}_onboardingtask" DisplayName="Onboarding Task" Description="Tracks specific tasks related to customer onboarding process" OwnershipType="UserOwned" IsAuditEnabled="true">
      <Attributes>
        <Attribute Name="onboardingtaskname" DisplayName="Task Name" Type="String" Length="100" Required="true" AuditEnabled="true" />
        <Attribute Name="description" DisplayName="Description" Type="Memo" Length="500" Required="false" AuditEnabled="true" />
        <!-- ownerid is OOB -->
      </Attributes>
      <Relationships>
        <Relationship Name="OnboardingTask_Contact" Type="ManyToOne" RelatedEntity="contact" />
        <Relationship Name="OnboardingTask_Checklist" Type="ManyToOne" RelatedEntity="${PublisherPrefix}_onboardingchecklist" />
      </Relationships>
      <Forms>
        <Form Name="Main Form" Type="Main" />
        <Form Name="Quick Create" Type="QuickCreate" />
        <Form Name="Quick View" Type="QuickView" />
      </Forms>
      <Views>
        <View Name="Active Onboarding Tasks" Type="Main" />
        <View Name="All Onboarding Tasks" Type="Main" />
        <View Name="My Onboarding Tasks" Type="Main" />
        <View Name="Completed Onboarding Tasks" Type="Main" />
        <View Name="Pending Approval Tasks" Type="Main" />
      </Views>
    </Entity>
  </Entities>
  <Roles>
    <Role Name="Onboarding Manager" Privileges="Read,Write,Create,Delete,Append,AppendTo,Assign,Share"/>
    <Role Name="Onboarding Agent" Privileges="Read,Write,Create,Append,AppendTo"/>
    <Role Name="Compliance Officer" Privileges="Read,Append,AppendTo"/>
  </Roles>
  <Dashboards>
    <Dashboard Name="Onboarding Overview Dashboard" />
    <Dashboard Name="Compliance Dashboard" />
  </Dashboards>
  <BusinessRules>
    <BusinessRule Name="Task Required Field Rule" Entity="${PublisherPrefix}_onboardingtask" />
    <BusinessRule Name="Due Date Validation" Entity="${PublisherPrefix}_onboardingtask" />
  </BusinessRules>
  <BusinessProcessFlows>
    <BusinessProcessFlow Name="Onboarding Task BPF" Entity="${PublisherPrefix}_onboardingtask" />
  </BusinessProcessFlows>
  </SolutionManifest>
</ImportExportXml>
"@
        Set-Content -Path (Join-Path $RootPath "customizations.xml") -Value $customizationsXml 

        # 3. [Content_Types].xml (Minimal, for import compatibility)
        $contentTypesXml = @"
<?xml version="1.0" ?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="xml" ContentType="application/xml"/>
    <Default Extension="png" ContentType="image/png"/>
    <Default Extension="js" ContentType="text/javascript"/>
</Types>
"@
        Set-Content -LiteralPath (Join-Path $RootPath "[Content_Types].xml") -Value $contentTypesXml 

        Write-Host "Created solution.xml, customizations.xml, [Content_Types].xml." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create XML files: $_"
        exit 1
    }
}

function Compress-D365CESolution {
    [CmdletBinding()]
    param (
        [string]$RootPath,
        [string]$SolutionName
    )
    try {
        $zipFile = "$RootPath\$SolutionName.zip"
        if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
        Compress-Archive -Path "$RootPath\*" -DestinationPath $zipFile -Force
        Write-Host "Compressed solution into $zipFile" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to compress solution: $_"
        exit 1
    }
}

function Test-SolutionXmlFiles {
    param (
        [string]$folderPath
    )
    
    $issues = @()
    
    # Check solution.xml
    $solutionXml = Join-Path $folderPath "solution.xml"
    if (Test-Path $solutionXml) {
        $xml = [xml](Get-Content $solutionXml)
        if ([string]::IsNullOrEmpty($xml.ImportExportXml.UniqueName)) {
            $issues += "solution.xml: UniqueName is empty"
        }
    }
    
    # Check customizations.xml
    $customizationsXml = Join-Path $folderPath "Customizations\customizations.xml"
    if (Test-Path $customizationsXml) {
        $xml = [xml](Get-Content $customizationsXml)
        $xml.ImportExportXml.Entities.Entity | ForEach-Object {
            if ([string]::IsNullOrEmpty($_.Name)) {
                $issues += "customizations.xml: Entity Name is empty"
            }
            $_.Attributes.Attribute | ForEach-Object {
                if ([string]::IsNullOrEmpty($_.Name)) {
                    $issues += "customizations.xml: Attribute Name is empty in entity $($_.ParentNode.ParentNode.Name)"
                }
            }
        }
    }
    
    return $issues
}

# Main execution in sequence
New-D365CESolutionFolderStructure -RootPath $RootPath
New-D365CESolutionXmlFiles -RootPath $RootPath -SolutionName $SolutionName -PublisherPrefix $PublisherPrefix -Version $Version
Compress-D365CESolution -RootPath $RootPath -SolutionName $SolutionName

Write-Host "Dynamics 365 CE solution package created and ready for import!" -ForegroundColor Cyan
Write-Host "Checking XML files for issues..." -ForegroundColor Yellow
# Check for issues in XML files 
$issues = Test-SolutionXmlFiles -folderPath $RootPath
write-host "Please check the folder $RootPath for the solution files." -ForegroundColor Yellow
if ($issues.Count -gt 0) {
    Write-Host "Issues found in XML files:" -ForegroundColor Red
    $issues | ForEach-Object { Write-Host $_ -ForegroundColor Red }
} else {
    Write-Host "No issues found in XML files." -ForegroundColor Green
}