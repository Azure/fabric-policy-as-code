function Test-FpacCICDEnvironment {
    foreach ($name in @('GITHUB_ACTIONS', 'TF_BUILD', 'GITLAB_CI', 'CI', 'BUILD_ID', 'CIRCLECI')) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            return $true
        }
    }
    return $false
}
