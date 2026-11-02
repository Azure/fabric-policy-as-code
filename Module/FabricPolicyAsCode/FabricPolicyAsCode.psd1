@{
    RootModule = 'FabricPolicyAsCode.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'f7d0de79-179b-41fd-92ed-30a88ebeb538'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'Export, plan, and deploy Microsoft Fabric Policy Sets as code.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    RequiredModules = @(@{ ModuleName = 'Az.Accounts'; ModuleVersion = '5.0.1' })
    FunctionsToExport = @('Export-FpacPolicy', 'New-FpacPolicyPlan', 'Invoke-FpacPolicyDeployment')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Fabric', 'Policy', 'Governance', 'PolicyAsCode', 'PSEdition_Core')
            LicenseUri = 'https://github.com/Azure/fabric-policy-as-code/blob/main/LICENSE'
            ProjectUri = 'https://github.com/Azure/fabric-policy-as-code'
            ReleaseNotes = 'Initial consumable module with export, planning, and guarded deployment commands. Fabric policy APIs are preview.'
        }
    }
}
