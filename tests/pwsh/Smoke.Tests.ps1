#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Smoke test -- quick green-flag check that delphi-msbuild.ps1 is present
  and its key functions load correctly via dot-source.

.DESCRIPTION
  This test is intentionally minimal.  A passing run confirms that the test
  runner, Pester configuration, and source script are all wired up correctly.
  It is not a substitute for the unit tests in delphi-msbuild.Tests.ps1.
#>

Describe 'delphi-msbuild.ps1 smoke test' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptPath = Get-ScriptUnderTestPath
    # Dot-source loads functions without executing the main flow
    # (the dot-source guard `if ($MyInvocation.InvocationName -eq '.') { return }`
    #  is present in the script).
    . $script:scriptPath
  }

  It 'source script exists on disk' {
    Test-Path -LiteralPath $script:scriptPath | Should -Be $true
  }

  It 'Resolve-RootDir function is available after dot-sourcing' {
    (Get-Command -Name Resolve-RootDir -CommandType Function -ErrorAction SilentlyContinue) |
      Should -Not -BeNull
  }

  It 'Invoke-MsbuildProject function is available after dot-sourcing' {
    (Get-Command -Name Invoke-MsbuildProject -CommandType Function -ErrorAction SilentlyContinue) |
      Should -Not -BeNull
  }

}
