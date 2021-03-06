function CompareValues {
    [CmdletBinding(DefaultParameterSetName="Value")]
    [OutputType([boolean], ParameterSetName="Value")]
    [OutputType([boolean], ParameterSetName="Scripted")]
    Param(
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [object]$ExpectedValue,
        
        [Parameter(Mandatory=$true, ParameterSetName='Value')]
        [AllowNull()]
        [object]$ActualValue,
        
        [Parameter(Mandatory=$true, ParameterSetName='Scripted')]
        [AllowNull()]
        [object]$ActualScripted,
        
        [Parameter(Mandatory=$false, ParameterSetName='Scripted')]
        [AllowEmptyCollection()]
        [HashTable]$Parameters = @{ },
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('eq', 'ne', 'is', 'isnot', 'gt', 'ge', 'lt', 'le', 'match', 'notmatch')]
        [string]$OperatorType
    )

    $errorColl = @();
    $actual = $null;
    if ($parasetname -eq 'scripted') {
        $cr = Get-CompositeResult -GetValue:$ActualScripted -Parameters:$Parameters;
        if ($cr.Errors.Length -gt 0) {
            foreach ($e in $cr.Errors) { $errColl = $errColl + $e }
        }
        if ($cr.ValueList.Length -eq 0) {
            $actual = $null;
        } else {
            if ($cr.ValueList.Length -eq 1) {
                $actual = $cr.ValueList[0];
            } else {
                $actual = $cr.ValueList;
            }
        }
    } else {
        $actual = $ActualValue;
    }
    
    $result = $null;

    switch ($OperatorType) {
            {$_ -eq 'eq'} {
               $result = ($expected -eq $actual);
               break;
            }
            {$_ -eq 'ne'} {
               $result = ($expected -ne $actual);
               break;
            }
            {$_ -eq 'is'} {
               $result = ($expected -is $actual);
               break;
            }
            {$_ -eq 'isnot'} {
               $result = (-not $expected -is $actual);
               break;
            }
            {$_ -eq 'gt'} {
               $result = ($expected -gt $actual);
               break;
            }
            {$_ -eq 'ge'} {
               $result = ($expected -ge $actual);
               break;
            }
            {$_ -eq 'lt'} {
               $result = ($expected -lt $actual);
               break;
            }
            {$_ -eq 'le'} {
               $result = ($expected -le $actual);
               break;
            }
            {$_ -eq 'match'} {
               $result = ($actual -match $expected);
               break;
            }
            {$_ -eq 'notmatch'} {
               $result = (-not $actual -eq $expected);
               break;
            }
            default { throw "Comparison type $_ is not supported." }
        }

    return $result;
}

function Is-NamedCustomType {
    Param(
        [Parameter(Mandatory=$true)]
        [object]$Value,

        [Parameter(Mandatory=$true)]
        [string]$TypeName,

        [Parameter(Mandatory=$false)]
        [switch]$CaseInsensitive
    )

    if ($Value -eq $null) {
        return ($TypeName -eq $null);
    }

    if ($Value.PSObject -eq $null -or $Value.PSObject.TypeNames -eq $null -or -not $Value.PSObject.TypeNames -is [string[]] -or $Value.PSObject.TypeNames.Length -eq 0) {
        return $false;
    }

    foreach ($tn in $Value.PSObject.TypeNames) {
        if ([System.String]::Compare($tn, $TypeName, $CaseInsensitive) -eq 0) { return $true; }
    }

    return $false;
}

function New-CompositeResult {
    <#
        .SYNOPSIS
            Create new CompositeResult custom object
        .DESCRIPTION
            Creates an object which encapsulates errors and values returned from function execution
        .EXAMPLE
            Add example here.
        .PARAMETER ErrorList
            Errors that occurred during execution
        .PARAMETER Result
            Output returned during execution
        .PARAMETER ErrorCaught
            Determines whether any errors were caught
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$ErrorList,
        
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Result,

        [Parameter(Mandatory=$true)]
        [boolean]$ErrorCaught
    )

    $valueList = $null;

    $compositeResult = New-Object PSObject;
    if ($Result -eq $null) {
        $valueList = @();
    } else {
        if ($result -is [Array]) {
            $valueList = $Result;
        } else {
            $valueList = @($Result);
        }
    }
    Add-Member -InputObject:$compositeResult -MemberType:NoteProperty -Name:'ErrorList' -Value:$ErrorList;
    Add-Member -InputObject:$compositeResult -MemberType:NoteProperty -Name:'ValueList' -Value:$valueList;
    Add-Member -InputObject:$compositeResult -MemberType:NoteProperty -Name:'RawResult' -Value:$Result;
    Add-Member -InputObject:$compositeResult -MemberType:NoteProperty -Name:'ErrorCaught' -Value:$ErrorCaught;

    $compositeResult.PSObject.TypeNames.Insert(0, 'CompositeResult');

    return $compositeResult;
}

function Get-CompositeResult {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$GetValue,
        
        [Parameter(Mandatory=$false)]
        [AllowEmptyCollection()]
        [HashTable]$Parameters = @{ },
        
        [Parameter(Mandatory=$false)]
        [AllowEmptyCollection()]
        [HashTable]$CompositeData = @{ },
        
        [Parameter(Mandatory=$false)]
        [switch]$ReturnsArray
    )

    $sb = {
        $el = @();
        $rl = $null;
        $ec = $false;
        try {
            $rl = &$GetValue @Parameters;
        } catch {
            $ec = $true;
            foreach ($e in $Error) { $el = $el + $e }
        }

        if ($rl -eq $null) {
            $rl = @();
        } else {
            if (-not $rl -is [object[]]) { $rl = @($rl) }
        }

        New-CompositeResult -ErrorList:$el -ValueList:$rl -ErrorCaught:$ec
    };

    $compositeResult = &$sb;

    if ((Is-NamedCustomType -Value $compositeResult -TypeName 'CompositeResult')) { return $compositeResult }

    $objArray = $compositeResult;
    $vl = @();
    $compositeResult = $null;
    foreach ($r in $objArray) {
        if ((Is-NamedCustomType -Value $r -TypeName 'CompositeResult') -and $compositeResult -eq $null) { 
            $compositeResult = $r;
        } else {
            $vl = $vl + $r;
        }
    }

    if ($compositeResult -eq $null) {
        $el = @();
        return New-CompositeResult -ErrorList:$el -ValueList:$vl -ErrorCaught:$false;
    } else {
        if ($vl.Length -gt 0) {
            foreach ($obj in $compositeResult.ValueList) { $vl = $vl + $obj }
        }

        return New-CompositeResult -ErrorList:$compositeResult.ErrorList -ValueList:$vl -ErrorCaught:$compositeResult.ErrorCaught;
    }
}

function New-PSUnitTestErrorReport {
    <#
        .SYNOPSIS
            Create new ErrorReport object
        .DESCRIPTION
            Creates an error report object
        .EXAMPLE
            Add example here.
        .PARAMETER Errors
            Errors that occurred during execution
        .PARAMETER Output
            Output received from unit test
        .PARAMETER Started
            Date and time when unit test was started
        .PARAMETER Finished
            Date and time when unit test finished
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({ if ($_.Length -eq 0) { Return $false }; foreach ($s in $_) { if ($s -eq $null) { Return $false } }; Return $true })]
        [Error[]]$Errors,
        
        [Parameter(Mandatory=$false)]
        [string]$CustomMessage = '',
        
        [Parameter(Mandatory=$true)]
        [string]$AssertMessage,
        
        [Parameter(Mandatory=$true)]
        [DateTime]$OccurredOn,
        
        [Parameter(Mandatory=$true)]
        [bool]$IsUnexpected
    );
    
    $result = New-Object PSObject;
    
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'Errors' -Value $Errors -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'CustomMessage' -Value $CustomMessage -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'AssertMessage' -Value $AssertMessage -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'OccurredOn' -Value $OccurredOn -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'IsUnexpected' -Value $IsUnexpected -Force;
    
    $result.PSTypeNames.Insert(0,'PSUnitTestErrorReport');
    
    return $result;
}

function Output-PSUnitTestErrorReport {
    <#
        .SYNOPSIS
            Create new ErrorReport object
        .DESCRIPTION
            Creates an error report object
        .EXAMPLE
            Add example here.
        .PARAMETER Errors
            Errors that occurred during execution
        .PARAMETER Output
            Output received from unit test
        .PARAMETER Started
            Date and time when unit test was started
        .PARAMETER Finished
            Date and time when unit test finished
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)]
        [string]$CustomMessage = '',
        
        [Parameter(Mandatory=$true)]
        [string]$AssertMessage,
        
        [Parameter(Mandatory=$true)]
        [bool]$IsUnexpected
    );
    
    $occurredOn = [DateTime]::Now;
    $errors = @();
    if ($error.Count -gt 0) {
        foreach ($e in $error) { $errors = $errors + $e }
    }
    $error.Clear();
    
    New-PSUnitTestErrorReport $errors $CustomMessage $AssertMessage $occurredOn $IsUnexpected;
}

function New-PSUnitTestExecutionResult {
    <#
        .SYNOPSIS
            Create new PSUnitTestExecutionResult object
        .DESCRIPTION
            Creates an execution result object
        .EXAMPLE
            Add example here.
        .PARAMETER Errors
            Errors that occurred during execution
        .PARAMETER Output
            Output received from unit test
        .PARAMETER Started
            Date and time when unit test was started
        .PARAMETER Finished
            Date and time when unit test finished
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({ if ($_.Length -eq 0) { Return $false }; foreach ($s in $_) { if ($s -eq $null) { Return $false } }; Return $true })]
        [PSUnitTestErrorReport[]]$ErrorReports,
        
        [Parameter(Mandatory=$true)]
        [string]$Output,
        
        [Parameter(Mandatory=$true)]
        [DateTime]$Started,
        
        [Parameter(Mandatory=$true)]
        [DateTime]$Finished,
        
        [Parameter(Mandatory=$true)]
        [bool]$ErrorCaught
    );
    
    $result = New-Object PSObject;
    
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'ErrorReports' -Value $ErrorReports -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'Output' -Value $Output -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'Started' -Value $Started -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'Finished' -Value $Finished -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'ErrorCaught' -Value $ErrorCaught -Force;
    
    $result.PSTypeNames.Insert(0,'PSUnitTestExecutionResult');
    
    return $result;
}

function New-PSUnitTest {
    <#
        .SYNOPSIS
            Create new PSUnitTest object
        .DESCRIPTION
            Creates a unit test object
        .EXAMPLE
            Add example here.
        .PARAMETER TestScript
            Test script to execute.
            2 parameters are passed to the test script:
                Parameter 0: The current unit test. Your script can use the Get-ContextObject and Set-ContextObject to access contextual information.
                Parameter 1: The current unit test list. Your script can use the Get-ContextObject and Set-ContextObject to access contextual information.
        .PARAMETER Name
            Name of unit test
        .PARAMETER Context
            Context object to associate with test script
        .PARAMETER ErrorAction
            ErrorActionPreference to use when running test script
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({ if ($_.Length -eq 0) { Return $false }; foreach ($s in $_) { if ($s -eq $null) { Return $false } }; Return $true })]
        [ScriptBlock]$TestScript,
        
        [Parameter(Mandatory=$false)]
        [ValidateScript({ $_.Length -gt 0 -and $_.Trim().Length -eq $_.Length })]
        [string]$Name = '',
        
        [Parameter(Mandatory=$false)]
        [object]$Context = $null,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Inquire', 'Continue', 'SilentlyContinue')]
        [string]$ErrorAction = ''
    );
    
    $result = @{ };
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'Name' -Value $Name -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'ErrorAction' -Value $ErrorAction -Force;
    Add-Member -InputObject $result -MemberType ScriptMethod -Name 'TestScript' -Value $TestScript -Force
    $result.PSTypeNames.Insert(0,'PSUnitTest');
    
    if ($PSBoundParameters.ContainsKey("Context")) { Set-PSUnitTestContext $result $Context }
    
    return $result;
}
    
function Get-PSUnitTestExecutionResult {
    <#
        .SYNOPSIS
            Get execution result from unit test
        .DESCRIPTION
            Gets the last execution result from unit test or null if unit test was never executed.
        .EXAMPLE
            Add example here.
        .PARAMETER UnitTest
            Unit test to retrieve results from
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTest]$UnitTest
    );
    
    if ($UnitTest.ContainsKey("ExecutionResult"))
        return $UnitTest["ExecutionResult"];
    
    return $null;
}

function Set-PSUnitTestExecutionResult {
    <#
        .SYNOPSIS
            Get execution result from unit test
        .DESCRIPTION
            Gets the last execution result from unit test or null if unit test was never executed.
        .EXAMPLE
            Add example here.
        .PARAMETER UnitTest
            Unit test to retrieve results from
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTest]$UnitTest,
        
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [PSUnitTestExecutionResult]$ExecutionResult
    )
    
    if ($UnitTest.ContainsKey("ExecutionResult")) {
        $UnitTest["ExecutionResult"] = $ExecutionResult;
    } else {
        $UnitTest.Add("ExecutionResult", $ExecutionResult);
    }
}

function Reset-AllPSUnitTests {
    <#
        .SYNOPSIS
            Resets all unit tests in test collection
        .DESCRIPTION
            Selects all unit tests and clears last execution result
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            List of unit tests to modify
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList
    )
    
    $allUnitTests = Get-PSUnitTestCollection $TestList;
    
    if ($allUnitTests.Count -eq 0) { Return }
    
    foreach ($ut in $allUnitTests) {
        Set-IsPSUnitTestSelected $ut $true;
        Set-PSUnitTestExecutionResult $ut $null;
    }
}

function Get-IsPSUnitTestSelected {
    <#
        .SYNOPSIS
            Get selection value for unit test
        .DESCRIPTION
            Determines whether a unit test is selected (flagged for execution).
        .EXAMPLE
            Add example here.
        .PARAMETER UnitTest
            Unit test to retrieve value from
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTest]$UnitTest
    )
    
    if ($UnitTest.ContainsKey("Selected"))
        return $UnitTest["Selected"];
    
    return $true;
}

function Set-IsPSUnitTestSelected {
    <#
        .SYNOPSIS
            Selects or deselects unit test
        .DESCRIPTION
            Selects or deselects a unit test to flag it for execution
        .EXAMPLE
            Add example here.
        .PARAMETER UnitTest
            Test script to modify
        .PARAMETER IsSelected
            Indicates whether unit test is selected for execution
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTest]$UnitTest,
        
        [Parameter(Mandatory=$true)]
        [boolean]$IsSelected
    )
    
    if ($UnitTest.ContainsKey("Selected")) {
        $UnitTest["Selected"] = $IsSelected;
    } else {
        $UnitTest.Add("Selected", $IsSelected);
    }
}

function Set-AllPSUnitTestsIsSelected {
    <#
        .SYNOPSIS
            Selects or deselects all unit tests in test collection
        .DESCRIPTION
            Selects or deselects all unit tests to flag them for execution
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            List of unit tests to modify
        .PARAMETER IsSelected
            Indicates whether all unit tests are selected for execution
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$true)]
        [boolean]$IsSelected
    )
    
    $allUnitTests = Get-PSUnitTestCollection $TestList;
    
    if ($allUnitTests.Count -eq 0) { Return }
    
    foreach ($ut in $allUnitTests) {
        Set-IsPSUnitTestSelected $ut $IsSelected
    }
}

function New-PSUnitTestList {
    <#
        .SYNOPSIS
            Create new PSUnitTestList object
        .DESCRIPTION
            Creates new PSUnitTestList to contain unit tests.
        .EXAMPLE
            Add example here.
        .PARAMETER Name
            Name of test list
        .PARAMETER UnitTests
            Unit tests Context add
        .PARAMETER UnitTests
            Context to associate with unit test
        .PARAMETER DefaultErrorAction
            Default ErrorActionPreference to use when running test scripts. Can be over-ridden by individual unit tests.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)]
        [ValidateScript({ $_.Length -gt 0 -and $_.Trim().Length -eq $_.Length })]
        [string]$Name = '',
        
        [Parameter(Mandatory=$false)]
        [ValidateScript({ if ($_.Length -eq 0) { Return $false }; foreach ($s in $_) { if ($s -eq $null) { Return $false } }; Return $true })]
        [PSUnitTest[]]$UnitTests,
        
        [Parameter(Mandatory=$false)]
        [object]$Context = $null,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Inquire', 'Continue', 'SilentlyContinue')]
        $DefaultErrorAction = 'SilentlyContinue'
    );
    
    $result = @{ Context = $Context; Tests = $testList };
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'Name' -Value $Name -Force;
    Add-Member -InputObject $result -MemberType NoteProperty -Name 'DefaultErrorAction' -Value $DefaultErrorAction -Force;
         
    $result.PSTypeNames.Insert(0,'PSUnitTestList');
    
    if ($PSBoundParameters.ContainsKey("UnitTests")) {
        foreach ($ut in $UnitTests) {
            Add-PSUnitTest -TestList:$testList -UnitTest:$ut;
        }
    }
    
    if ($PSBoundParameters.ContainsKey("Context")) { Set-PSUnitTestContext $result $Context }
    
    return $result;
}

function Add-PSUnitTest {
    <#
        .SYNOPSIS
            Add PSUnitTest object to PSUnitTestList
        .DESCRIPTION
            Adds a unit test to a unit test list
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            List to add unit test to
        .PARAMETER UnitTest
            Unit test to add.
            This parameter con only be used with -TestList.
        .PARAMETER Name
            Name of new unit test.
            This parameter cannot be used with -UnitTest.
        .PARAMETER TestScript
            Test script for new unit test
            This parameter cannot be used with -UnitTest.
        .PARAMETER Context
            Context object to associate with new unit test
            This parameter cannot be used with -UnitTest.
    #>
    [CmdletBinding(DefaultParameterSetName="FromUnitTestParameters")]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$true, ParameterSetName="FromUnitTestObject")]
        [PSUnitTest]$UnitTest,
        
        [Parameter(Mandatory=$false, ParameterSetName="FromUnitTestParameters")]
        [ValidateScript({ $_.Length -gt 0 -and $_.Trim().Length -eq $_.Length })]
        [string]$Name = '',
        
        [Parameter(Mandatory=$true, ParameterSetName="FromUnitTestParameters")]
        [ScriptBlock]$TestScript,
        
        [Parameter(Mandatory=$false, ParameterSetName="FromUnitTestParameters")]
        [object]$Context = $null
    );
    
    $ut = $null;
    if ($PsCmdlet.ParameterSetName -eq "FromUnitTestObject") {
        $existingItem = Get-PSUnitTestByName $TestList, $UnitTest.Name;
        if ($existingItem -ne $null) { throw 'A unit test with that name already exists.' }
        $ut = $UnitTest;
    } else {
        if ($PSBoundParameters.ContainsKey("Name")) {
            $existingItem = Get-PSUnitTestByName $TestList, $Name;
            if ($existingItem -ne $null) { throw 'A unit test with that name already exists.' }
        }
        
        $PSBoundParameters.Remove("TestList");
        $ut = New-PSUnitTest @PSBoundParameters;
    }
    
    $allUnitTests = Get-PSUnitTestCollection $TestList;
    
    $allUnitTests.Add($ut);
}

function Get-PSUnitTestCollection {
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList
    );
    
    if ($TestList.ContainsKey("Tests")) {
        if ($TestList["Tests"] -is 'System.Collections.ObjectModel.Collection[PSUnitTest]') { return $TestList["Tests"] }
        [void]$TestList.Remove("Tests");
    }
    
    $result = New-Object -Type System.Collections.ObjectModel.Collection[PSUnitTest];
    
    $TestList.Add("Tests", $result);
    
    return $result;
}

function Get-PSUnitTests {
    <#
        .SYNOPSIS
            Gets array of unit tests associated with a test collection
        .DESCRIPTION
            Returns an array of tests, optionally matching -IsSelected
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            List to get unit tests from
        .PARAMETER IsSelected
            Filters results by selection status
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$false)]
        [boolean]$IsSelected
    );
    
    $allUnitTests = Get-PSUnitTestCollection $TestList;
    
    $result = @();
    
    if ($allUnitTests.Count -eq 0) { return $result; }
    
    if ($PSBoundParameters.ContainsKey("IsSelected")) {
        foreach ($ut in $allUnitTests) { 
            $selected = Get-IsPSUnitTestSelected $ut;
            if ($selected -eq $IsSelected) { $result = $result + $t }
        }
    } else {
        foreach ($ut in $allUnitTests) { $result = $result + $t }
    }
    
    return $result;
}

function Get-PSUnitTestByName {
    <#
        .SYNOPSIS
            Get unit test by name
        .DESCRIPTION
            Returns unit test matching -Name or null if no tests matched the specified name
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            List to get unit test from
        .PARAMETER Name
            Name of test list
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$true)]
        [string]$Name
    );
    
    $allUnitTests = Get-PSUnitTestCollection $TestList;
    
    if ($allUnitTests.Count -eq 0) { return $null }
    
    foreach ($ut in $allUnitTests) {
        if ($ut.Name.Length -gt 0 -and $ut.Name -eq $Name) { return $ut }
    }
    
    return $null;
}

function Remove-PSUnitTestByName {
    <#
        .SYNOPSIS
            Get unit test by name
        .DESCRIPTION
            Returns unit test matching -Name or null if no tests matched the specified name
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            List to get unit test from
        .PARAMETER Name
            Name of test list
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$true)]
        [string]$Name
    );
    
    $allUnitTests = Get-PSUnitTestCollection $TestList;
    
    if ($allUnitTests.Count -eq 0) { return $false }
    
    foreach ($ut in $allUnitTests) {
        if ($ut.Name.Length -gt 0 -and $ut.Name -eq $Name) { 
            $allUnitTests.Remove($ut);
            return;
        }
    }
    
    return $false;
}

function Get-PSUnitTestByIndex {
    <#
        .SYNOPSIS
            Get unit test by name
        .DESCRIPTION
            Returns unit test at index -Index or null if index was out of range.
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            List to get unit test from
        .PARAMETER Index
            Name of test list
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$true)]
        [int]$Index
    );
    
    $allUnitTests = Get-PSUnitTestCollection $TestList;
    
    if ($Index -lt 0 -or $Index -ge $allUnitTests.Count) { return $null }
    
    return $allUnitTests[$Index];
}

function Remove-PSUnitTestByIndex {
    <#
        .SYNOPSIS
            Get unit test by name
        .DESCRIPTION
            Returns unit test at index -Index or null if index was out of range.
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            List to get unit test from
        .PARAMETER Index
            Name of test list
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$true)]
        [int]$Index
    );
    
    $allUnitTests = Get-PSUnitTestCollection $TestList;
    
    if ($allUnitTests.Count -eq 0 -or $Index -lt 0 -or $Index -ge $allUnitTests.Count) { return $false }
    
    $allUnitTests.Remove($allUnitTests[$Index]);
}

function Get-ContextObject {
    <#
        .SYNOPSIS
            Gets context object associated with a PSUnitTest or a PSUnitTestList
        .DESCRIPTION
            Gets context object associated with a unit test or a unit test collection
        .EXAMPLE
            Add example here.
        .PARAMETER UnitTest
            Unit test to retrieve context from.
            This parameter cannot be used with -TestList.
        .PARAMETER TestList
            Test list to retrieve context from.
            This parameter cannot be used with -UnitTest.
    #>
    [CmdletBinding(DefaultParameterSetName="UnitTest")]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="UnitTest")]
        [PSUnitTest]$UnitTest,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="TestList")]
        [PSUnitTestList]$TestList
    );
    
    if ($PsCmdlet.ParameterSetName -eq "UnitTest") { 
        if ($UnitTest.ContainsKey("Context")) { return $UnitTest["Context"] }
    } else {
        if ($TestList.ContainsKey("Context")) { return $TestList["Context"] }
    }
    
    return $null;
}

function Set-ContextObject {
    <#
        .SYNOPSIS
            Associates context object
        .DESCRIPTION
            Associates context object with unit test or test list
        .EXAMPLE
            Add example here.
        .PARAMETER UnitTest
            Unit test to set context to.
            This parameter cannot be used with -TestList.
        .PARAMETER TestList
            Test list to set context to.
            This parameter cannot be used with -UnitTest.
        .PARAMETER Context
            Context to apply to unit test or test list
    #>
    [CmdletBinding(DefaultParameterSetName="UnitTest")]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="UnitTest")]
        [PSUnitTest]$UnitTest,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="TestList")]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$true, ParameterSetName="UnitTest")]
        [Parameter(Mandatory=$true, ParameterSetName="TestList")]
        [AllowNull()]
        [object]$Context
    );
    
    if ($PsCmdlet.ParameterSetName -eq "UnitTest") { 
        if ($UnitTest.ContainsKey("Context")) {
            $UnitTest["Context"] = $Context;
        } else {
            $UnitTest.Add("Context", $Context);
        }
    } else {
        if ($TestList.ContainsKey("Context")) {
            $TestList["Context"] = $Context;
        } else {
            $TestList.Add("Context", $Context);
        }
    }
}

function Run-PSUnitTest {
    <#
        .SYNOPSIS
            Runs unit test
        .DESCRIPTION
            Runs unit test and sets PSUnitTestExecutionResult
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            Test list to set context to.
        .PARAMETER Index
            Index of unit test to run
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$true)]
        [int]$Index,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Inquire', 'Continue', 'SilentlyContinue')]
        $DefaultErrorAction
    );
    
    $unitTest = Get-PSUnitTestByIndex $TestList, $Index;
    
    if ($unitTest -eq $null) { throw 'Index out of range' }
    
    $testScript = $unitTest.TestScript;
    
    if ($UnitTest.ErrorAction -eq '') {
        $ErrorActionPreference = $TestList.DefaultErrorAction;
    } else {
        $ErrorActionPreference = $UnitTest.ErrorAction;
    }
    
    $started = [DateTime]::Now();
    $finished = $null;
    $errors = $null;
    $output = $null;
    $errorCaught = $false;
    
    $Error.Clear();
    
    try {
        $output = &$testScript $unitTest $TestList;
        $end = [DateTime]::Now();
    } catch {
        $errorCaught = $true;
        $end = [DateTime]::Now();
    }
    finally {
        $ErrorActionPreference = $currentPreference;
    }
    
    $er = New-PSUnitTestExecutionResult $Errors, $Output, $Started, $Finished, $ErrorCaught;
    Set-PSUnitTestExecutionResult $UnitTest $er;
    
    return $unitTest;
}

function Run-PSUnitTestList {
    <#
        .SYNOPSIS
            Runs unit tests associated with a test collection
        .DESCRIPTION
            Runs unit tests, matching -IsSelected
        .EXAMPLE
            Add example here.
        .PARAMETER TestList
            List to get unit tests from
        .PARAMETER IsSelected
            Filters results by selection status. Default value is $true.
            This parameter cannot be used with -RunAllTests.
        .PARAMETER RunAllTests
            Runs all tests regardless of selection status.
            This parameter cannot be used with -IsSelected.
    #>
    [CmdletBinding(DefaultParameterSetName="RunSelectedTests")]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [PSUnitTestList]$TestList,
        
        [Parameter(Mandatory=$false, ParameterSetName="RunSelectedTests")]
        [boolean]$IsSelected = $true,
        
        [Parameter(Mandatory=$true, ParameterSetName="RunAllTests")]
        [switch]$RunAllTests
    );
    
    if ($PsCmdlet.ParameterSetName -eq "RunAllTests") { [void]$PSBoundParameters.Remove("RunAllTests") }

    $testsToRun = Get-PSUnitTestCollection @PSBoundParameters;    

    $results = @();
    
    if ($testsToRun.Count -eq 0) { return $results; }
    
    for ($index=0; $index < $testsToRun.Count; $index++) { 
        $unitTest = Run-PSUnitTest $TestList $index;
        $results = $results + $unitTest;    $er = Get-PSUnitTestExecutionResult $unitTest;
        if (-not $er.ErrorCaught -and $er.Errors.Length -eq 0) {
            Set-IsPSUnitTestSelected $unitTest $false;
        }
    }
    
    return $results;
}

function Assert-IsTrue {
    <#
        .SYNOPSIS
            Asserts whether value is true
        .DESCRIPTION
            Throws error if value is not true
        .EXAMPLE
            Add example here.
        .PARAMETER Value
            Value to assert
        .PARAMETER ScriptedValue
            Result from script execution is asserted to be true.
        .PARAMETER CustomMessage
            Custom Message to include with assertion failure.
    #>
    [CmdletBinding(DefaultParameterSetName="Value")]
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="Value")]
        [boolean]$Value = $true,
        
        [Parameter(Mandatory=$true, ParameterSetName="Script")]
        [ScriptBlock]$ScriptedValue,
        
        [Parameter(Mandatory=$false)]
        [string]$CustomMessage
    );
    
    if ($PsCmdlet.ParameterSetName -eq "Value") {
        Assert-Equals -ExpectedValue:$true -ActualValue:$Value -CustomMessage:$CustomMessage
    } else {
        Assert-Equals -ExpectedValue:$true -ScriptedActual:$ScriptedValue -CustomMessage:$CustomMessage
    }
}

function Assert-Equals {
    <#
        .SYNOPSIS
            Asserts whether values are equal
        .DESCRIPTION
            Throws error if values are not equal
        .EXAMPLE
            Add example here.
        .PARAMETER ExpectedValue
            Expected value
        .PARAMETER ActualValue
            Actual value
        .PARAMETER ScriptedActual
            Actual value obtained from scriptblock.
        .PARAMETER CustomMessage
            Custom Message to include with assertion failure.
        .PARAMETER StrictTypeMatch
            Whether to also assert that the types are the same.
    #>
    [CmdletBinding(DefaultParameterSetName="Value")]
    Param(
        [Parameter(Mandatory=$true)]
        [object]$ExpectedValue,

        [Parameter(Mandatory=$true, ParameterSetName="Value")]
        [object]$ActualValue,
        
        [Parameter(Mandatory=$true, ParameterSetName="Script")]
        [ScriptBlock]$ScriptedActual,
        
        [Parameter(Mandatory=$false)]
        [string]$CustomMessage,
        
        [Parameter(Mandatory=$false)]
        [switch]$StrictTypeMatch
    );
    
    $actual = $null;
    if ($PsCmdlet.ParameterSetName -eq "Value") {
        $actual = $ActualValue;
    } else {
        $isCaught = $false;
        
        try {
            $actual = &$ScriptedActual;
        } catch {
            $actual = $false;
            $isCaught = $true;
        }
    
        if ($isCaught) {
            Output-PSUnitTestErrorReport $CustomMessage, 'Exception was caught', $true;
            Return;
        }
    }
    
    $result = $null;
    $message = $null;
    if ($StrictTypeMatch) {
        if ($ExpectedValue -eq $null -or $actual -eq $null) {
            return ($ExpectedValue -eq $null) -eq ($actual -eq $null)
        }

        $expectedTypeName = Get-DefaultPSTypeName $ExpectedValue;
                
        if (-not $actual -is $expectedTypeName) {
            $result = $false;
            $message = "Expected Type: $expectedTypeName; Actual Type: $(Get-DefaultPSTypeName $actual)";
        } else {
            try {
                $result = ($ExpectedValue -eq $actual);
            } catch {
                $result = $false;
                $message = 'Values could not be compared for equality. Expected: $(Get-StringValueQuoted $ExpectedValue); Actual: $(Get-StringValueQuoted $actual)';
            }
        }
    } else {
        try {
            $result = ($expected -eq $actual);
        } catch {
            $result = $false;
            $message = 'Values could not be compared for equality. Expected: $(Get-StringValueQuoted $ExpectedValue); Actual: $(Get-StringValueQuoted $actual)';
        }
    }
    
    if ($result) {
        if ($error.Count -gt 0) {
            Output-PSUnitTestErrorReport $CustomMessage, 'Test successful, but with errors', $false;
        }
        
        Return;
    }
    
    if ($message -eq $null) { $message = "Expected: $(Get-StringValueQuoted $ExpectedValue); Actual: $(Get-StringValueQuoted $actual)"; }
    
    Output-PSUnitTestErrorReport $CustomMessage, $message, $false;
}

function Assert-NotEquals {
    <#
        .SYNOPSIS
            Asserts whether values are equal
        .DESCRIPTION
            Throws error if values are not equal
        .EXAMPLE
            Add example here.
        .PARAMETER UnexpectedValue
            Expected value
        .PARAMETER ActualValue
            Actual value
        .PARAMETER ScriptedActual
            Actual value obtained from scriptblock.
        .PARAMETER CustomMessage
            Custom Message to include with assertion failure.
        .PARAMETER StrictTypeMatch
            Whether to also assert that the types are not the same.
    #>
    [CmdletBinding(DefaultParameterSetName="Value")]
    Param(
        [Parameter(Mandatory=$true)]
        [object]$UnexpectedValue,

        [Parameter(Mandatory=$true, ParameterSetName="Value")]
        [object]$ActualValue,
        
        [Parameter(Mandatory=$true, ParameterSetName="Script")]
        [ScriptBlock]$ScriptedActual,
        
        [Parameter(Mandatory=$false)]
        [string]$CustomMessage,
        
        [Parameter(Mandatory=$false)]
        [switch]$StrictTypeMatch
    );
    
    $actual = $null;
    if ($PsCmdlet.ParameterSetName -eq "Value") {
        $actual = $ActualValue;
    } else {
        $isCaught = $false;
        try {
            $actual = &$ScriptedActual;
        } catch {
            $actual = $false;
            $isCaught = $true;
        }
    
        if ($isCaught) {
            Output-PSUnitTestErrorReport $CustomMessage, 'Exception was caught', $true;
            Return;
        }
    }
    
    $result = $null;
    $message = $null;
    $unexpectedTypeName = Get-DefaultPSTypeName $UnexpectedValue;
    
    if ($StrictTypeMatch) {
        if ($UnexpectedValue -eq $null) {
            if ($actual -eq $null) {
                $result = $false;
            } else {
                $result = $true;
            }
        } else {
            if ($actual -eq $null) {
                $result = $true;
            } else {
                if ($actual -is $unexpectedTypeName) {
                    try {
                        $result = ($UnexpectedValue -ne $actual);
                    } catch {
                        $result = $false;
                        $message = 'Values could not be compared for equality. Expected: $(Get-StringValueQuoted $UnexpectedValue); Actual: $(Get-StringValueQuoted $actual)';
                    }
                } else {
                    $result = $true;
                }
            }
        }
    } else {
        try {
            $result = ($expected -ne $actual);
        } catch {
            $result = $false;
            $message = 'Values could not be compared for equality. Expected: $(Get-StringValueQuoted $UnexpectedValue); Actual: $(Get-StringValueQuoted $actual)';
        }
    }
    
    if ($result) {
        if ($error.Count -gt 0) {
            Output-PSUnitTestErrorReport $CustomMessage, 'Test successful, but with errors', $false;
        }
        
        Return;
    }
    
    if ($message -eq $null) {
        $actualTypeName = Get-DefaultPSTypeName $actual;
        if ($unexpectedTypeName -eq $actualTypeName) {
            $message = "Unexpected: $(Get-StringValueQuoted $UnexpectedValue)";
        } else {
            $message = "Types were not the same, but evaluated as being equal. Unexpected Value: $(Get-StringValueQuoted $UnexpectedValue); Unexpected Type: $unexpectedTypeName; Actual Type: $actualTypeName";
        }
    }
    
    Output-PSUnitTestErrorReport $CustomMessage, $message, $false;
}

function Get-DefaultPSTypeName {
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="Value")]
        [object]$obj
    )
    
    $psTypeNames = $obj.PSTypeNames;
    if ($psTypeNames -eq $null -or $psTypeNames.Count -eq 0)
        return $obj.GetType().FullName;
    
    return $psTypeNames[0];
}

function Get-StringValueQuoted {
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="Value")]
        [object]$obj
    )
    
    if ($obj -eq $null) { return 'null' }
    
    $result = $obj.ToString();
    
    $tn = Get-DefaultPSTypeName $obj;
    if ($result -eq $tn)
        return "[$result]";
        
    return "'$($result.Replace("\", "\\").Replace("'", "\'"))'";
}