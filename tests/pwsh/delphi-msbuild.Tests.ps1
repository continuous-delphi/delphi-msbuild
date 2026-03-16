#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for delphi-msbuild.ps1

.DESCRIPTION
  Covers the pure helper functions and mockable build flow.
  No tests invoke MSBuild or cmd.exe directly.

  Describe 1 - Resolve-RootDir:
    Explicit -RootDir takes precedence over pipeline object.
    Pipeline .rootDir used when no explicit param.
    Returns null when neither source provides a value.
    Returns null when pipeline object has null/empty rootDir.
    Returns null when pipeline object has no rootDir property.

  Describe 2 - Get-RsvarsPath:
    Derives bin\rsvars.bat path from rootDir.

  Describe 3 - Invoke-RsvarsEnvironment:
    Applies KEY=VALUE lines to process environment.
    Throws when Get-RsvarsEnvLines returns zero parseable lines.
    Propagates throw from Get-RsvarsEnvLines (rsvars.bat exit failure).

  Describe 4 - Invoke-MsbuildProject:
    Passes correct MSBuild arguments to Invoke-MsbuildExe.
    Forwards -ShowOutput switch to Invoke-MsbuildExe.
    Returns the result object from Invoke-MsbuildExe.

  Describe 5 - Main flow (via Invoke-ToolProcess, no MSBuild calls):
    Exits 3 when no rootDir is provided (no pipeline, no -RootDir).
    Exits 3 when rootDir directory does not exist on disk.
    Exits 3 when rsvars.bat is absent under rootDir.
    Exits 4 when project file does not exist.
#>

Describe 'Resolve-RootDir' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-MsBuildScriptPath)
  }

  It 'returns explicit RootDir when provided' {
    $result = Resolve-RootDir -ExplicitRootDir 'C:\Explicit\Root' -Installation $null
    $result | Should -Be 'C:\Explicit\Root'
  }

  It 'explicit RootDir takes precedence over pipeline .rootDir' {
    $inst = [pscustomobject]@{ rootDir = 'C:\From\Pipeline' }
    $result = Resolve-RootDir -ExplicitRootDir 'C:\Explicit\Root' -Installation $inst
    $result | Should -Be 'C:\Explicit\Root'
  }

  It 'returns pipeline .rootDir when no explicit param' {
    $inst = [pscustomobject]@{ rootDir = 'C:\From\Pipeline' }
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $inst
    $result | Should -Be 'C:\From\Pipeline'
  }

  It 'returns null when neither source provides a value' {
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $null
    $result | Should -BeNull
  }

  It 'returns null when pipeline object has null rootDir' {
    $inst = [pscustomobject]@{ rootDir = $null }
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $inst
    $result | Should -BeNull
  }

  It 'returns null when pipeline object has empty rootDir' {
    $inst = [pscustomobject]@{ rootDir = '   ' }
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $inst
    $result | Should -BeNull
  }

  It 'returns null when pipeline object has no rootDir property' {
    $inst = [pscustomobject]@{ verDefine = 'VER360' }
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $inst
    $result | Should -BeNull
  }

}

Describe 'Get-RsvarsPath' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-MsBuildScriptPath)
  }

  It 'produces the rsvars.bat path under the bin subdirectory' {
    $root   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'fake-delphi', '23.0')
    $result = Get-RsvarsPath -RootDir $root
    $result | Should -Be ([System.IO.Path]::Combine($root, 'bin', 'rsvars.bat'))
  }

  It 'handles trailing separator in rootDir' {
    $root   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'fake-delphi', '23.0')
    $sep    = [System.IO.Path]::DirectorySeparatorChar
    $result = Get-RsvarsPath -RootDir "${root}${sep}"
    $result | Should -Be ([System.IO.Path]::Combine($root, 'bin', 'rsvars.bat'))
  }

}

Describe 'Invoke-RsvarsEnvironment' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-MsBuildScriptPath)
  }

  Context 'applies environment variables from Get-RsvarsEnvLines output' {

    BeforeAll {
      Mock Get-RsvarsEnvLines {
        return @(
          'BDS=C:\RAD\Studio\23.0',
          'BDSBIN=C:\RAD\Studio\23.0\bin',
          'PATH=C:\RAD\Studio\23.0\bin;C:\Windows'
        )
      }
      Invoke-RsvarsEnvironment -RsvarsPath 'C:\RAD\Studio\23.0\bin\rsvars.bat'
    }

    It 'sets BDS in process environment' {
      [Environment]::GetEnvironmentVariable('BDS', 'Process') | Should -Be 'C:\RAD\Studio\23.0'
    }

    It 'sets BDSBIN in process environment' {
      [Environment]::GetEnvironmentVariable('BDSBIN', 'Process') | Should -Be 'C:\RAD\Studio\23.0\bin'
    }

    It 'calls Get-RsvarsEnvLines with the rsvars path' {
      # Must call inside It so Pester 5 tracks it in this test's call history
      Mock Get-RsvarsEnvLines { return @('BDSBIN=C:\RAD\Studio\23.0\bin') }
      Invoke-RsvarsEnvironment -RsvarsPath 'C:\RAD\Studio\23.0\bin\rsvars.bat'
      Should -Invoke Get-RsvarsEnvLines -ParameterFilter {
        $RsvarsPath -eq 'C:\RAD\Studio\23.0\bin\rsvars.bat'
      } -Times 1 -Exactly
    }

  }

  Context 'throws when Get-RsvarsEnvLines returns no parseable lines' {

    BeforeAll {
      Mock Get-RsvarsEnvLines { return @() }
    }

    It 'throws with a descriptive message' {
      { Invoke-RsvarsEnvironment -RsvarsPath 'C:\fake\rsvars.bat' } |
        Should -Throw -ExpectedMessage '*no environment variables*'
    }

  }

  Context 'propagates throw from Get-RsvarsEnvLines' {

    BeforeAll {
      Mock Get-RsvarsEnvLines { throw 'rsvars.bat exited with code 1 : C:\bad\rsvars.bat' }
    }

    It 'throws the error from Get-RsvarsEnvLines' {
      { Invoke-RsvarsEnvironment -RsvarsPath 'C:\bad\rsvars.bat' } |
        Should -Throw -ExpectedMessage '*rsvars.bat exited with code 1*'
    }

  }

}

Describe 'Invoke-MsbuildProject' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-MsBuildScriptPath)
  }

  Context 'assembles correct MSBuild arguments' {

    BeforeAll {
      # Capture args in BeforeAll so It blocks can assert on them without
      # re-calling the function (Pester 5 resets Should -Invoke history per It).
      $script:capturedArgs     = $null
      $script:capturedShowOutput = $false
      Mock Invoke-MsbuildExe {
        $script:capturedArgs       = $Arguments
        $script:capturedShowOutput = [bool]$ShowOutput
        return [pscustomobject]@{ ExitCode = 0; Output = 'build ok' }
      }

      Invoke-MsbuildProject `
        -ProjectFile  'C:\Projects\MyApp.dproj' `
        -Platform     'Win32' `
        -Config       'Release' `
        -Target       'Build' `
        -Verbosity    'minimal'
    }

    It 'passes ProjectFile as first argument' {
      $script:capturedArgs[0] | Should -Be 'C:\Projects\MyApp.dproj'
    }

    It 'passes /t:<Target>' {
      $script:capturedArgs | Should -Contain '/t:Build'
    }

    It 'passes /p:Config=<Config>' {
      $script:capturedArgs | Should -Contain '/p:Config=Release'
    }

    It 'passes /p:Platform=<Platform>' {
      $script:capturedArgs | Should -Contain '/p:Platform=Win32'
    }

    It 'passes /v:<Verbosity>' {
      $script:capturedArgs | Should -Contain '/v:minimal'
    }

  }

  Context 'forwards ShowOutput switch' {

    BeforeAll {
      $script:capturedShowOutput = $false
      Mock Invoke-MsbuildExe {
        $script:capturedShowOutput = [bool]$ShowOutput
        return [pscustomobject]@{ ExitCode = 0; Output = $null }
      }

      Invoke-MsbuildProject `
        -ProjectFile 'C:\Projects\MyApp.dproj' `
        -Platform    'Win32' `
        -Config      'Debug' `
        -Target      'Build' `
        -Verbosity   'normal' `
        -ShowOutput
    }

    It 'passes ShowOutput=$true to Invoke-MsbuildExe' {
      $script:capturedShowOutput | Should -Be $true
    }

  }

  Context 'returns the result object from Invoke-MsbuildExe' {

    BeforeAll {
      Mock Invoke-MsbuildExe {
        return [pscustomobject]@{ ExitCode = 42; Output = 'some output' }
      }
      $script:result = Invoke-MsbuildProject `
        -ProjectFile 'C:\Projects\MyApp.dproj' `
        -Platform    'Win32' `
        -Config      'Debug' `
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'result ExitCode matches Invoke-MsbuildExe return' {
      $script:result.ExitCode | Should -Be 42
    }

    It 'result Output matches Invoke-MsbuildExe return' {
      $script:result.Output | Should -Be 'some output'
    }

  }

  Context 'Rebuild target is passed correctly' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile 'C:\Projects\MyApp.dproj' `
        -Platform    'Win32' `
        -Config      'Debug' `
        -Target      'Rebuild' `
        -Verbosity   'normal'
    }

    It 'passes /t:Rebuild' {
      $script:capturedArgs | Should -Contain '/t:Rebuild'
    }

  }

}

Describe 'Main flow -- pre-MSBuild validation (no MSBuild invoked)' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptPath = Get-MsBuildScriptPath
  }

  Context 'exits 3 when no rootDir is provided and no pipeline input' {

    BeforeAll {
      # No -RootDir, no pipeline -- must exit 3 before reaching MSBuild
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dproj'
      )
    }

    It 'exit code is 3' {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr contains helpful message' {
      $script:result.StdErr -join ' ' | Should -Match 'root dir'
    }

  }

  Context 'exits 3 when rootDir directory does not exist on disk' {

    BeforeAll {
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dproj',
        '-RootDir',     'C:\DoesNotExist\AtAll\9999'
      )
    }

    It 'exit code is 3' {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions the missing directory' {
      $script:result.StdErr -join ' ' | Should -Match 'not found'
    }

  }

  Context 'exits 3 when rootDir exists but rsvars.bat is absent' {

    BeforeAll {
      # Use a real directory that exists on all platforms but has no rsvars.bat
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dproj',
        '-RootDir',     ([System.IO.Path]::GetTempPath())
      )
    }

    It 'exit code is 3' {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions rsvars.bat' {
      $script:result.StdErr -join ' ' | Should -Match 'rsvars\.bat'
    }

  }

  Context 'exits 4 when rsvars.bat exists but project file does not' {

    BeforeAll {
      # Create a temporary rsvars.bat so the rootDir check passes, then use a
      # non-existent project file path.
      $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-msbuild-test'
      $script:tempBin  = Join-Path $script:tempRoot 'bin'
      $null = New-Item -ItemType Directory -Path $script:tempBin -Force
      $null = New-Item -ItemType File -Path (Join-Path $script:tempBin 'rsvars.bat') -Force

      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\DoesNotExist.dproj',
        '-RootDir',     $script:tempRoot
      )
    }

    AfterAll {
      Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exit code is 4' {
      $script:result.ExitCode | Should -Be 4
    }

    It 'stderr mentions the missing project file' {
      $script:result.StdErr -join ' ' | Should -Match 'not found'
    }

  }

}
