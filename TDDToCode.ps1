<#
.SYNOPSIS
Automates setup for Dynamics 365 CE solution from attached TDD.

.PARAMETER CompanyName
Company prefix for solution/project naming.

.PARAMETER DryRun
If set, simulates actions and logs steps, but does not perform changes.
#>

param(
  [Parameter(Mandatory)]
  [string]$CompanyName,
  [switch]$DryRun
)

function Write-Log { param($msg) ; Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn { param($msg) ; Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-ErrorExit { param($msg) ; Write-Host "[ERROR] $msg" -ForegroundColor Red ; exit 1 }

try {
    # 1. Download TDD if needed
    $tddUrl = "https://github.com/amey201078/TestPrompts/raw/main/MJINC_Financial%20Service_TDD_v0.3.txt"
    $tddFile = "MJINC_Financial Service_TDD_v0.3.txt"
    if (!(Test-Path $tddFile)) {
        Write-Log "Downloading TDD file from $tddUrl"
        if (-not $DryRun) { Invoke-WebRequest -Uri $tddUrl -OutFile $tddFile }
        Write-Log "TDD file downloaded to $PWD\$tddFile"
    } else {
        Write-Log "TDD file already present: $PWD\$tddFile"
    }
    $tddContent = Get-Content $tddFile -Raw

    # 2. Parse TDD for solution name
    if ($tddContent -match "(?i)Technical Design Document.*?Financial Services Enhancements for Dynamics 365 CE") {
        $solutionNameRaw = "FinancialServicesEnhancements"
    } else {
        $solutionNameRaw = "D365CESolution"
        Write-Warn "Falling back to generic solution name."
    }
    $solutionName = "$CompanyName.$solutionNameRaw"

    # 2. Parse plugins
    $pluginBlocks = @()
    $pluginPattern = "(?ms)7\.1 KYC Completion Plugin\s*If user attempts to close an Opportunity:([\s\S]+?)Else:\s*Allow Opportunity to be closed\."
    $pluginMatches = [regex]::Matches($tddContent, $pluginPattern)
    foreach ($m in $pluginMatches) {
        $pluginCode = @"
using System;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;

public class KycCompletionPlugin : IPlugin
{
    public void Execute(IServiceProvider serviceProvider)
    {
        var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
        var serviceFactory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
        var service = serviceFactory.CreateOrganizationService(context.UserId);
        if (context.MessageName == "Close" && context.InputParameters.Contains("Target") && context.InputParameters["Target"] is Entity entity)
        {
            if (entity.LogicalName != "opportunity") return;
            var accountRef = entity.GetAttributeValue<EntityReference>("accountid");
            if (accountRef == null) return;
            var kycQuery = new QueryExpression("kycdocument");
            kycQuery.ColumnSet = new ColumnSet("status");
            kycQuery.Criteria.AddCondition("accountid", ConditionOperator.Equal, accountRef.Id);
            var kycDocs = service.RetrieveMultiple(kycQuery);
            foreach (var kyc in kycDocs.Entities) {
                var status = kyc.GetAttributeValue<OptionSetValue>("status")?.Value;
                if (status != 3) {
                    throw new InvalidPluginExecutionException("Complete all KYC before closing opportunity.");
                }
            }
        }
    }
}
"@
        $pluginBlocks += @{ Name = "KycCompletionPlugin"; Code = $pluginCode }
    }

    # 2. Parse JavaScript web resource (allocation rule example)
    $jsBlocks = @()
    $jsPattern = "(?ms)7\.4 Allocation Rule \(JavaScript/Plugin\)([\s\S]+?)Allow save\."
    $jsMatches = [regex]::Matches($tddContent, $jsPattern)
    foreach ($m in $jsMatches) {
        $jsCode = @"
function validateOpportunityLineAllocation(executionContext) {
    var formContext = executionContext.getFormContext();
    var oppLines = formContext.getAttribute('opportunitylines').getValue();
    var total = 0;
    if (oppLines && Array.isArray(oppLines)) {
        for (var i = 0; i < oppLines.length; i++) {
            var allocation = oppLines[i].allocationpercentage;
            if (allocation) total += allocation;
        }
    }
    if (total > 100) {
        formContext.ui.setFormNotification('Total allocation exceeds 100\\%', 'ERROR', 'allocationerror');
        executionContext.getEventArgs().preventDefault();
    }
}
"@
        $jsCode = $jsCode -replace "'", "\\'"
        $jsBlocks += @{ Name = "validateOpportunityLineAllocation"; Code = $jsCode }
    }

    Write-Log "Solution Name: $solutionName"
    Write-Log "Plugin code blocks found: $($pluginBlocks.Count)"
    Write-Log "JS code blocks found: $($jsBlocks.Count)"

    # 3. Solution and Project Scaffolding
    $root = Join-Path $PWD $solutionName
    if (!(Test-Path $root)) {
        if (-not $DryRun) { New-Item -ItemType Directory $root | Out-Null }
        Write-Log "Created solution root: $root"
    }
    Push-Location $root

    $dotnetCmd = "dotnet"

    if (-not (Test-Path "$root\$solutionName.sln")) {
        if (-not $DryRun) { & $dotnetCmd new sln -n $solutionName }
        Write-Log "Created .NET solution: $solutionName.sln"
    }

    # Plugins Project
    $pluginsProj = "$CompanyName.Plugins"
    if (!(Test-Path "$root\$pluginsProj")) {
        if (-not $DryRun) {
            & $dotnetCmd new classlib -n $pluginsProj
            (Get-Content "$pluginsProj\$pluginsProj.csproj") -replace "<TargetFramework>.*</TargetFramework>", "<TargetFramework>net462</TargetFramework>" | Set-Content "$pluginsProj\$pluginsProj.csproj"
            & $dotnetCmd sln add "$pluginsProj\$pluginsProj.csproj"
        }
        Write-Log "Created Plugins project ($pluginsProj)"
    }
    # WebResources Project
    $webProj = "$CompanyName.WebResources"
    if (!(Test-Path "$root\$webProj")) {
        if (-not $DryRun) {
            & $dotnetCmd new classlib -n $webProj
            (Get-Content "$webProj\$webProj.csproj") -replace "<TargetFramework>.*</TargetFramework>", "<TargetFramework>net462</TargetFramework>" | Set-Content "$webProj\$webProj.csproj"
            & $dotnetCmd sln add "$webProj\$webProj.csproj"
        }
        Write-Log "Created WebResources project ($webProj)"
    }

    # 4. Plugin Project Configuration
    if (-not $DryRun) {
        Push-Location $pluginsProj
        & $dotnetCmd add package Microsoft.CrmSdk.CoreAssemblies
        & $dotnetCmd add package Microsoft.CrmSdk.Workflow

        # 7. Locate sn.exe
        $snExe = Get-ChildItem -Path "C:\Program Files*", "C:\Program Files (x86)*" -Recurse -Filter sn.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if (!$snExe) { Write-ErrorExit "sn.exe not found. Please install Visual Studio developer tools." }
        $snPath = $snExe.FullName

        # Generate .snk file and sign assembly
        $snkFile = "$pluginsProj.snk"
        if (!(Test-Path $snkFile)) {
            & "$snPath" -k $snkFile
            Write-Log "Generated strong name key: $snkFile using $snPath"
        }

        # Set assembly sign in .csproj, add xml nodes to first <PropertyGroup>
        $csprojPath = "$pluginsProj.csproj"
        $csproj = Get-Content $csprojPath
        $firstPropIdx = ($csproj | Select-String "<PropertyGroup>").LineNumber[0] - 1
        $insertNodes = @(
            "    <SignAssembly>true</SignAssembly>",
            "    <AssemblyOriginatorKeyFile>$snkFile</AssemblyOriginatorKeyFile>",
            "    <LangVersion>10.0</LangVersion>"
        )
        if ($csproj -notmatch "<SignAssembly>true</SignAssembly>") {
            $newCsproj = @()
            for ($i = 0; $i -lt $csproj.Count; $i++) {
                $line = $csproj[$i]
                $newCsproj += $line
                if ($i -eq $firstPropIdx) { $newCsproj += $insertNodes }
            }
            Set-Content $csprojPath $newCsproj
            Write-Log "Injected signing and LangVersion nodes in $csprojPath"
        }

        # Create Plugins folder and inject plugin class file(s)
        $pluginsDir = "Plugins"
        if (!(Test-Path $pluginsDir)) { mkdir $pluginsDir | Out-Null }
        foreach ($plugin in $pluginBlocks) {
            $pluginClassName = $plugin.Name
            $pluginFile = Join-Path $pluginsDir "$pluginClassName.cs"
            Set-Content $pluginFile $plugin.Code
            Write-Log "Created plugin class file: $pluginFile"
        }
        Pop-Location
    }

    # 5. Web Resources Project Configuration
    if (-not $DryRun -and $jsBlocks.Count -gt 0) {
        Push-Location $webProj
        $jsDir = "js"
        if (!(Test-Path $jsDir)) { mkdir $jsDir | Out-Null }
        foreach ($js in $jsBlocks) {
            $jsName = $js.Name
            $jsFile = Join-Path $jsDir "$jsName.js"
            Set-Content $jsFile $js.Code
            Write-Log "Created JS web resource file: $jsFile"
        }
        Pop-Location
    }

    # 6. Update csproj language version if <Nullable>enable</Nullable> is found (ignore WebResources)
    $csprojFiles = Get-ChildItem -Path $root -Recurse -Filter *.csproj | Where-Object { $_.Name -notmatch "WebResources" }
    foreach ($proj in $csprojFiles) {
        $projPath = $proj.FullName
        $projContent = Get-Content $projPath
        $hasNullable = $projContent -match "<Nullable>enable</Nullable>"
        $langVersion = ($projContent | Select-String "<LangVersion>(.+?)</LangVersion>").Matches.Groups[1].Value
        if ($hasNullable -and (!$langVersion -or [version]$langVersion -lt [version]"10.0")) {
            $newContent = @()
            $inPropGroup = $false
            foreach ($line in $projContent) {
                $newContent += $line
                if ($line -match "<PropertyGroup>") { $inPropGroup = $true }
                if ($inPropGroup -and $line -notmatch "<LangVersion>") {
                    $newContent += "    <LangVersion>10.0</LangVersion>"
                    $inPropGroup = $false
                }
            }
            Set-Content $projPath $newContent
            Write-Log "Updated LangVersion to 10.0 in $projPath"
        }
    }

    # 8. Delete Class1.cs from all projects
    $class1Files = Get-ChildItem -Path $root -Recurse -Filter Class1.cs
    foreach ($cls in $class1Files) {
        if (-not $DryRun) { Remove-Item $cls.FullName -Force }
        Write-Log "Deleted $($cls.FullName)"
    }

    # 9. Set <Build>false</Build> in .sln-included WebResources projects
    $slnFile = Get-ChildItem -Path $root -Filter *.sln | Select-Object -First 1
    if ($slnFile) {
        $slnContent = Get-Content $slnFile.FullName
        $csprojPaths = ($slnContent | Where-Object { $_ -match 'Project\(".*"\) = "([^"]+)", "([^"]+\.csproj)"' }) | ForEach-Object {
            $_ -replace '.*",\s*"(.*?)".*', '$1'
        }
        foreach ($projRelPath in $csprojPaths) {
            if ($projRelPath -match "WebResources") {
                $projAbsPath = Join-Path $root $projRelPath
                if (Test-Path $projAbsPath) {
                    $projContent = Get-Content $projAbsPath
                    $projContent = $projContent -replace '(?ms)(<ProjectConfiguration[^>]*>[\s\S]*?<Build>)(true)(</Build>)', '${1}false${3}'
                    Set-Content $projAbsPath $projContent
                    Write-Log "Set <Build>false</Build> in $projAbsPath"
                }
            }
        }
    }

    # 10. Build Plugins Project
    if (-not $DryRun) {
        Write-Log "Building plugins project..."
        & $dotnetCmd build "$pluginsProj\$pluginsProj.csproj" -c Release
        Write-Log "Plugins project build complete."
    }

    Write-Log "Setup complete. Dry-run: $DryRun"
    Pop-Location
}
catch {
    Write-ErrorExit "Exception: $_"
}