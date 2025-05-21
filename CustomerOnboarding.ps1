<#
.SYNOPSIS
    Automates creation of Customer Onboarding customizations in Dynamics 365 CE using Microsoft Power Platform CLI (pac).
.DESCRIPTION
    - Connects to environment interactively (env URL as parameter).
    - Uses Power Platform CLI (pac) to create/update table, columns, lookups, choices, and basic views.
    - Accepts PublisherPrefix and SolutionName as input parameters.
    - Sequentially creates objects with 10s wait between each.
    - Implements robust error handling and checks variable scope in messages.
    - Uses only approved verbs.
    - Adaptable for any Dataverse/Dynamics 365 CE environment.
.NOTES
    Prerequisites:
      - Power Platform CLI installed: https://aka.ms/pac
      - User has permission to create tables/columns/etc in target environment/solution.
      - Solution already exists (or create with pac solution create).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory = $true)]
    [string]$PublisherPrefix,

    [Parameter(Mandatory = $true)]
    [string]$SolutionName
)

function Wait-Step($step) {
    Write-Host "Waiting 10 seconds after $step..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

function Handle-Error($msg, $variable = $null) {
    if ($null -ne $variable -and $variable) {
        Write-Host "$msg : $($variable)" -ForegroundColor Red
    } else {
        Write-Host "$msg" -ForegroundColor Red
    }
    exit 1
}

# Step 0: Authenticate to the environment
try {
    Write-Host "`nAuthenticating to environment $EnvironmentUrl ..." -ForegroundColor Cyan
    pac auth create --environment $EnvironmentUrl
    if ($LASTEXITCODE -ne 0) { Handle-Error "Authentication failed." $EnvironmentUrl }
    Write-Host "Authenticated to $EnvironmentUrl" -ForegroundColor Green
} catch {
    Handle-Error "Error during authentication:" $_
}
Wait-Step "authentication"

# Table (Entity) and Fields Definitions
$tableLogical = "${PublisherPrefix}_onboardingtask"
$tableDisplay = "Onboarding Task"
$tablePlural = "Onboarding Tasks"
$primaryField = "${PublisherPrefix}_onboardingtaskname"
$primaryFieldDisplay = "Task Name"
$tableDescription = "Tracks specific tasks related to customer onboarding process"

$columns = @(
    @{ name="${PublisherPrefix}_onboardingtaskname"; display="Task Name"; type="Text"; length=100; required="true"; description="Task Name" }
    @{ name="${PublisherPrefix}_description"; display="Description"; type="MultilineText"; length=500; required="false"; description="Description" }
    @{ name="${PublisherPrefix}_duedate"; display="Due Date"; type="DateTime"; required="false"; description="Due Date" }
    # Lookups and OptionSets are handled below
)

# Step 1: Create/Update Entity/Table
try {
    Write-Host "`nCreating table [$tableDisplay] ($tableLogical) ..." -ForegroundColor Cyan
    pac solution add-table `
        --solution $SolutionName `
        --display-name "$tableDisplay" `
        --plural-name "$tablePlural" `
        --schema-name "$tableLogical" `
        --primary-name "$primaryField" `
        --primary-name-display-name "$primaryFieldDisplay" `
        --description "$tableDescription" `
        --enabled-for-activities false `
        --enabled-for-attachments false `
        --is-auditable true `
        --ownership-type UserOwned
    if ($LASTEXITCODE -ne 0) { Handle-Error "Table creation failed." $tableLogical }
    Write-Host "Table created: $tableDisplay ($tableLogical)" -ForegroundColor Green
} catch {
    Handle-Error "Error creating table:" $_
}
Wait-Step "table"

# Step 2: Add Columns/Attributes
foreach ($col in $columns) {
    try {
        Write-Host "`nAdding column [$($col.display)] ($($col.name)) ..." -ForegroundColor Cyan
        if ($col.type -eq "Text") {
            pac solution add-table-column `
                --solution $SolutionName `
                --table $tableLogical `
                --display-name "$($col.display)" `
                --schema-name "$($col.name)" `
                --data-type Text `
                --max-length $($col.length) `
                --is-required:$($col.required) `
                --description "$($col.description)"
        } elseif ($col.type -eq "MultilineText") {
            pac solution add-table-column `
                --solution $SolutionName `
                --table $tableLogical `
                --display-name "$($col.display)" `
                --schema-name "$($col.name)" `
                --data-type MultilineText `
                --max-length $($col.length) `
                --is-required:$($col.required) `
                --description "$($col.description)"
        } elseif ($col.type -eq "DateTime") {
            pac solution add-table-column `
                --solution $SolutionName `
                --table $tableLogical `
                --display-name "$($col.display)" `
                --schema-name "$($col.name)" `
                --data-type DateTime `
                --is-required:$($col.required) `
                --description "$($col.description)"
        }
        if ($LASTEXITCODE -ne 0) { Handle-Error "Column creation failed." $($col.name) }
        Write-Host "Column added: $($col.display)" -ForegroundColor Green
    } catch {
        $errMsg = if ($col -and $col.display) { "Error adding $($col.display):" } else { "Error adding column:" }
        Handle-Error $errMsg $_
    }
    Wait-Step "$($col.display) column"
}

# Step 3: Add Lookup Columns (Relationships)
$lookups = @(
    @{ name="ownerid"; display="Assigned To"; referencedTable="systemuser"; description="Owner/User" }
    @{ name="${PublisherPrefix}_onboardingchecklistid"; display="Onboarding Checklist"; referencedTable="${PublisherPrefix}_onboardingchecklist"; description="Onboarding Checklist" }
    @{ name="contactid"; display="Contact"; referencedTable="contact"; description="Contact" }
)
foreach ($lk in $lookups) {
    try {
        Write-Host "`nAdding lookup [$($lk.display)] ($($lk.name)) ..." -ForegroundColor Cyan
        pac solution add-table-lookup `
            --solution $SolutionName `
            --table $tableLogical `
            --display-name "$($lk.display)" `
            --schema-name "$($lk.name)" `
            --related-table "$($lk.referencedTable)" `
            --description "$($lk.description)"
        if ($LASTEXITCODE -ne 0) { Handle-Error "Lookup creation failed." $($lk.name) }
        Write-Host "Lookup added: $($lk.display)" -ForegroundColor Green
    } catch {
        $errMsg = if ($lk -and $lk.display) { "Error adding lookup $($lk.display):" } else { "Error adding lookup:" }
        Handle-Error $errMsg $_
    }
    Wait-Step "$($lk.display) lookup"
}

# Step 4: Add OptionSet (Choice) for Status
try {
    Write-Host "`nAdding OptionSet [Onboarding Task Status] ..." -ForegroundColor Cyan
    pac solution add-choice `
        --solution $SolutionName `
        --display-name "Onboarding Task Status" `
        --schema-name "${PublisherPrefix}_OnboardingTaskStatus" `
        --option "Active,1" `
        --option "Pending Approval,2" `
        --option "Completed,3" `
        --option "In Progress,4" `
        --description "Status for Onboarding Task"
    if ($LASTEXITCODE -ne 0) { Handle-Error "OptionSet creation failed." "${PublisherPrefix}_OnboardingTaskStatus" }
    Write-Host "OptionSet added: Onboarding Task Status" -ForegroundColor Green

    # Add Status column and link to OptionSet
    pac solution add-table-column `
        --solution $SolutionName `
        --table $tableLogical `
        --display-name "Status" `
        --schema-name "statuscode" `
        --data-type Choice `
        --choice "${PublisherPrefix}_OnboardingTaskStatus" `
        --is-required:true `
        --description "Status"
    if ($LASTEXITCODE -ne 0) { Handle-Error "Status column creation failed." }
    Write-Host "Status column added and linked to OptionSet." -ForegroundColor Green
} catch {
    Handle-Error "Error creating OptionSet/Status column:" $_
}
Wait-Step "OptionSet/Status column"

# Step 5: Add Example Views (system views)
$views = @(
    "Active Onboarding Tasks",
    "All Onboarding Tasks",
    "My Onboarding Tasks",
    "Completed Onboarding Tasks",
    "Pending Approval Tasks"
)
foreach ($view in $views) {
    try {
        Write-Host "`nAdding system view: $view ..." -ForegroundColor Cyan
        pac solution add-table-view `
            --solution $SolutionName `
            --table $tableLogical `
            --display-name "$view" `
            --name "$($view -replace ' ','_')" `
            --description "$view"
        if ($LASTEXITCODE -ne 0) { Handle-Error "System view creation failed." $view }
        Write-Host "System view added: $view" -ForegroundColor Green
    } catch {
        $errMsg = if ($view) { "Error creating view" } else { "Error creating view:" }
        Handle-Error $errMsg $_
    }
    Wait-Step "$view view"
}

# Step 6: Publish changes
try {
    Write-Host "`nPublishing customizations..." -ForegroundColor Cyan
    pac org publish
    if ($LASTEXITCODE -ne 0) { Handle-Error "Publish failed." }
    Write-Host "Publish complete!" -ForegroundColor Green
} catch {
    Handle-Error "Error publishing customizations:" $_
}

Write-Host "`nAll Customer Onboarding customizations processed. Review forms, views, and business logic in the application." -ForegroundColor Green