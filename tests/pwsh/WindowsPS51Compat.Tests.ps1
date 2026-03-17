#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Windows PowerShell 5.1 compatibility tests for delphi-msbuild.ps1.

.DESCRIPTION
  Verifies that delphi-msbuild.ps1 can be launched under powershell.exe
  (Windows PowerShell 5.1) and produces correct exit codes.
  All tests in this file skip automatically on platforms where
  powershell.exe is absent (e.g. Linux CI runners).

  The test suite itself continues to require pwsh 7+ (see run-tests.ps1);
  these tests only invoke the script-under-test via powershell.exe.

  Scenarios tested:
    Exits 3 when no -RootDir and no pipeline input.
    Exits 3 when -RootDir directory does not exist on disk.
    Exits 3 when -RootDir exists but rsvars.bat is absent.
    Exits 4 when rsvars.bat exists but -ProjectFile does not.

.NOTES
  Get-Command is NOT used to locate powershell.exe.  The Invoke-RsvarsEnvironment
  unit test applies fake environment variables (including a truncated PATH) to the
  live process, which removes C:\Windows\System32\WindowsPowerShell\v1.0 from PATH
  and breaks Get-Command resolution for external commands.  Instead, powershell.exe
  is located via its well-known fixed path under $env:SystemRoot.  On Linux/macOS
  $env:SystemRoot is absent so Test-Path returns $false and all tests skip cleanly.

  $skipTests is a discovery-time local variable captured by -Skip:.
  $script:winPS51Exe is set in BeforeAll (run time) so it is visible in
  It and Context BeforeAll blocks.

  -ExecutionPolicy Bypass is passed to powershell.exe because the machine's
  default execution policy may not permit running unsigned scripts.
#>

Describe 'Windows PowerShell 5.1 compatibility' {

  # Evaluated at Pester discovery time -- captured by -Skip: on each It.
  # Uses Test-Path (filesystem) rather than Get-Command (PATH-dependent) to
  # locate powershell.exe safely regardless of prior process PATH changes.
  $ps51Path  = if ($env:SystemRoot) {
    [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  } else { $null }
  $skipTests = -not ($ps51Path -and (Test-Path -LiteralPath $ps51Path))

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptPath = Get-ScriptUnderTestPath

    $script:winPS51Exe = $null
    $sysRoot = $env:SystemRoot
    if ($sysRoot) {
      $candidate = [System.IO.Path]::Combine($sysRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
      if (Test-Path -LiteralPath $candidate) { $script:winPS51Exe = $candidate }
    }
  }

  It 'powershell.exe (Windows PowerShell 5.1) is present on this machine' -Skip:$skipTests {
    $script:winPS51Exe | Should -Not -BeNullOrEmpty
  }

  Context 'exits 3 when no rootDir is provided and no pipeline input' {

    BeforeAll {
      if (-not $script:winPS51Exe) { return }
      $script:result = Invoke-ToolProcess `
        -Shell           $script:winPS51Exe `
        -ExecutionPolicy 'Bypass' `
        -ScriptPath      $script:scriptPath `
        -Arguments       @('-ProjectFile', 'C:\Fake\MyApp.dproj')
    }

    It 'exit code is 3' -Skip:$skipTests {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr contains helpful message' -Skip:$skipTests {
      $script:result.StdErr -join ' ' | Should -Match 'root dir'
    }

  }

  Context 'exits 3 when rootDir directory does not exist on disk' {

    BeforeAll {
      if (-not $script:winPS51Exe) { return }
      $script:result = Invoke-ToolProcess `
        -Shell           $script:winPS51Exe `
        -ExecutionPolicy 'Bypass' `
        -ScriptPath      $script:scriptPath `
        -Arguments       @('-ProjectFile', 'C:\Fake\MyApp.dproj', '-RootDir', 'C:\DoesNotExist\AtAll\9999')
    }

    It 'exit code is 3' -Skip:$skipTests {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions the missing directory' -Skip:$skipTests {
      $script:result.StdErr -join ' ' | Should -Match 'not found'
    }

  }

  Context 'exits 3 when rootDir exists but rsvars.bat is absent' {

    BeforeAll {
      if (-not $script:winPS51Exe) { return }
      $script:result = Invoke-ToolProcess `
        -Shell           $script:winPS51Exe `
        -ExecutionPolicy 'Bypass' `
        -ScriptPath      $script:scriptPath `
        -Arguments       @('-ProjectFile', 'C:\Fake\MyApp.dproj', '-RootDir', ([System.IO.Path]::GetTempPath()))
    }

    It 'exit code is 3' -Skip:$skipTests {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions rsvars.bat' -Skip:$skipTests {
      $script:result.StdErr -join ' ' | Should -Match 'rsvars\.bat'
    }

  }

  Context 'exits 4 when rsvars.bat exists but project file does not' {

    BeforeAll {
      if (-not $script:winPS51Exe) { return }
      $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-msbuild-winps51-test'
      $script:tempBin  = Join-Path $script:tempRoot 'bin'
      $null = New-Item -ItemType Directory -Path $script:tempBin -Force
      $null = New-Item -ItemType File -Path (Join-Path $script:tempBin 'rsvars.bat') -Force

      $script:result = Invoke-ToolProcess `
        -Shell           $script:winPS51Exe `
        -ExecutionPolicy 'Bypass' `
        -ScriptPath      $script:scriptPath `
        -Arguments       @('-ProjectFile', 'C:\Fake\DoesNotExist.dproj', '-RootDir', $script:tempRoot)
    }

    AfterAll {
      if ($script:tempRoot) {
        Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
      }
    }

    It 'exit code is 4' -Skip:$skipTests {
      $script:result.ExitCode | Should -Be 4
    }

    It 'stderr mentions the missing project file' -Skip:$skipTests {
      $script:result.StdErr -join ' ' | Should -Match 'not found'
    }

  }

}
