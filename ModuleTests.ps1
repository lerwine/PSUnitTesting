$error.Clear();
$configurationModulePreloaded = Get-Module 'PSUnitTesting';
if ($configurationModulePreloaded -ne $null) { Remove-Module 'PSUnitTesting' }
$path = [System.IO.Path]::Combine((Split-Path -Parent $MyInvocation.MyCommand.Path), 'Configuration');
Import-Module $path;

function Test-New-CompositeResult {
}

if ($error.Count -gt 0) {
    Write-Error $error;
    Write-Host 'Test failed due to errors.';
    Return;
}

$oldErrorActionPreference = $ErrorActionPreference;

try {
    Test-New-CompositeResult;

    
} catch {
    Write-Error $error;
    Write-Host 'Test failed due to errors.';
    $error.Clear();
}
finally {
    $ErrorActionPreference = $oldErrorActionPreference
}