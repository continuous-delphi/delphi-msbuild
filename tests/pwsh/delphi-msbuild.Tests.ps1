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
    Passes WinARM64EC platform through to MSBuild arguments.
    Forwards -ShowOutput switch to Invoke-MsbuildExe.
    Returns the result object from Invoke-MsbuildExe.
    ExeOutputDir adds /p:DCC_ExeOutput; omitted adds nothing.
    DcuOutputDir adds /p:DCC_DcuOutput; omitted adds nothing.
    UnitSearchPath single entry appends with $(DCC_UnitSearchPath) prefix.
    UnitSearchPath multiple entries joined with semicolons.
    UnitSearchPath omitted adds no /p:DCC_UnitSearchPath argument.
    Omits /p:DCC_Define when no defines are supplied.
    Appends /p:DCC_Define with $(DCC_Define) prefix for a single define.
    Appends /p:DCC_Define with $(DCC_Define) prefix for multiple defines.
    Property omitted adds no extra /p: argument.
    Property single entry becomes /p:Key=Value (unquoted when clean).
    Property multiple entries emitted in sorted key order.
    Property value containing spaces is passed verbatim (unquoted).
    Property value containing semicolons is passed verbatim (unquoted).
    Property is appended after built-ins (override precedence).
    BuildAllUnits switch adds /p:DCC_BuildAllUnits=true; omitted adds nothing.
    EnvLibraryPath adds /p:_EnvLibraryPath (unquoted); omitted adds nothing.
    EnvLibraryPath trailing separator is trimmed; drive root is preserved.
    UnitSearchPath trailing separator on each entry is trimmed.
    BuildAllUnits remains overridable via -Property (override appears later).
    MsbuildPath is forwarded to Invoke-MsbuildExe; omitted forwards empty.

  Describe 5 - Main flow (via Invoke-ToolProcess, no MSBuild calls):
    Exits 3 when no rootDir is provided (no pipeline, no -RootDir).
    Exits 3 when rootDir directory does not exist on disk.
    Exits 3 when rsvars.bat is absent under rootDir.
    Exits 4 when project file does not exist.
    Exits 2 when -MsbuildPath does not exist.
    Exits 2 when -MsbuildPath is a directory (not a file).
    -SkipRsvars bypasses rootDir/rsvars requirement (exits 4, not 3).

  Describe 6 - Get-PathWithoutTrailingSeparator:
    Trims a trailing backslash; leaves an interior/none-present value intact;
    preserves a drive-root separator; returns empty/all-separator input unchanged.

  Describe 6b - Test-NativeQuotingRisk:
    Flags a value with whitespace AND a trailing backslash; nothing else.

  Describe 7 - Native argument passing (real arg-echo exe, Windows only):
    A /p: value ending in a backslash reaches the child process as one intact
    argument, with following arguments preserved as separate argv elements.
    Under PS 5.1, an unquotable -Property value (whitespace + trailing backslash)
    produces a clear warning naming the property.
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

  Context 'WinARM64EC platform is passed correctly' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile 'C:\Projects\MyApp.dproj' `
        -Platform    'WinARM64EC' `
        -Config      'Debug' `
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'passes /p:Platform=WinARM64EC' {
      $script:capturedArgs | Should -Contain '/p:Platform=WinARM64EC'
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

  Context 'ExeOutputDir adds /p:DCC_ExeOutput' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile  'C:\Projects\MyApp.dproj' `
        -Platform     'Win32' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -ExeOutputDir 'C:\Build\bin'
    }

    It 'includes /p:DCC_ExeOutput=C:\Build\bin' {
      $script:capturedArgs | Should -Contain '/p:DCC_ExeOutput=C:\Build\bin'
    }

  }

  Context 'ExeOutputDir omitted adds no /p:DCC_ExeOutput argument' {

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
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'no argument contains DCC_ExeOutput' {
      ($script:capturedArgs | Where-Object { $_ -like '*DCC_ExeOutput*' }) | Should -BeNullOrEmpty
    }

  }

  Context 'DcuOutputDir adds /p:DCC_DcuOutput' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile  'C:\Projects\MyApp.dproj' `
        -Platform     'Win32' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -DcuOutputDir 'C:\Build\dcu'
    }

    It 'includes /p:DCC_DcuOutput=C:\Build\dcu' {
      $script:capturedArgs | Should -Contain '/p:DCC_DcuOutput=C:\Build\dcu'
    }

  }

  Context 'DcuOutputDir omitted adds no /p:DCC_DcuOutput argument' {

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
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'no argument contains DCC_DcuOutput' {
      ($script:capturedArgs | Where-Object { $_ -like '*DCC_DcuOutput*' }) | Should -BeNullOrEmpty
    }

  }

  Context 'UnitSearchPath single entry appends with $(DCC_UnitSearchPath) prefix' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile    'C:\Projects\MyApp.dproj' `
        -Platform       'Win32' `
        -Config         'Debug' `
        -Target         'Build' `
        -Verbosity      'normal' `
        -UnitSearchPath @('C:\Libs\MyLib')
    }

    It 'includes /p:DCC_UnitSearchPath=$(DCC_UnitSearchPath);C:\Libs\MyLib (unquoted)' {
      $script:capturedArgs | Should -Contain '/p:DCC_UnitSearchPath=$(DCC_UnitSearchPath);C:\Libs\MyLib'
    }

  }

  Context 'UnitSearchPath multiple entries are joined with semicolons' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile    'C:\Projects\MyApp.dproj' `
        -Platform       'Win32' `
        -Config         'Debug' `
        -Target         'Build' `
        -Verbosity      'normal' `
        -UnitSearchPath @('C:\Libs\A', 'C:\Libs\B')
    }

    It 'includes /p:DCC_UnitSearchPath=$(DCC_UnitSearchPath);C:\Libs\A;C:\Libs\B (unquoted)' {
      $script:capturedArgs | Should -Contain '/p:DCC_UnitSearchPath=$(DCC_UnitSearchPath);C:\Libs\A;C:\Libs\B'
    }

  }

  Context 'UnitSearchPath omitted adds no /p:DCC_UnitSearchPath argument' {

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
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'no argument contains DCC_UnitSearchPath' {
      ($script:capturedArgs | Where-Object { $_ -like '*DCC_UnitSearchPath*' }) | Should -BeNullOrEmpty
    }

  }

  Context 'omits /p:DCC_Define when no -Define values are supplied' {

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
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'does not include any /p:DCC_Define argument' {
      $script:capturedArgs | Should -Not -Contain { $_ -like '/p:DCC_Define=*' }
      ($script:capturedArgs | Where-Object { $_ -like '/p:DCC_Define=*' }) | Should -BeNullOrEmpty
    }

  }

  Context 'appends /p:DCC_Define with $(DCC_Define) prefix for a single define' {

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
        -Target      'Build' `
        -Verbosity   'normal' `
        -Define      @('MYFLAG')
    }

    It 'includes /p:DCC_Define=$(DCC_Define);MYFLAG (unquoted)' {
      $script:capturedArgs | Should -Contain '/p:DCC_Define=$(DCC_Define);MYFLAG'
    }

  }

  Context 'appends /p:DCC_Define with $(DCC_Define) prefix for multiple defines' {

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
        -Target      'Build' `
        -Verbosity   'normal' `
        -Define      @('MYFLAG', 'USE_JEDI_JCL')
    }

    It 'includes /p:DCC_Define=$(DCC_Define);MYFLAG;USE_JEDI_JCL (unquoted)' {
      $script:capturedArgs | Should -Contain '/p:DCC_Define=$(DCC_Define);MYFLAG;USE_JEDI_JCL'
    }

  }

  Context 'Property omitted adds no extra /p: argument' {

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
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'passes only the six baseline arguments' {
      $script:capturedArgs.Count | Should -Be 6
    }

  }

  Context 'Property single entry becomes /p:Key=Value' {

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
        -Target      'Build' `
        -Verbosity   'normal' `
        -Property    @{ DCC_BuildAllUnits = 'true' }
    }

    It 'includes /p:DCC_BuildAllUnits=true unquoted' {
      $script:capturedArgs | Should -Contain '/p:DCC_BuildAllUnits=true'
    }

  }

  Context 'Property multiple entries are emitted in sorted key order' {

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
        -Target      'Build' `
        -Verbosity   'normal' `
        -Property    @{ Zeta = '1'; Alpha = '2' }
    }

    It 'includes /p:Alpha=2' {
      $script:capturedArgs | Should -Contain '/p:Alpha=2'
    }

    It 'includes /p:Zeta=1' {
      $script:capturedArgs | Should -Contain '/p:Zeta=1'
    }

    It 'emits Alpha before Zeta (deterministic sort)' {
      $alphaIdx = [array]::IndexOf($script:capturedArgs, '/p:Alpha=2')
      $zetaIdx  = [array]::IndexOf($script:capturedArgs, '/p:Zeta=1')
      $alphaIdx | Should -BeLessThan $zetaIdx
    }

  }

  Context 'Property value containing spaces is passed verbatim (unquoted)' {

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
        -Target      'Build' `
        -Verbosity   'normal' `
        -Property    @{ _EnvLibraryPath = 'C:\Program Files\Lib' }
    }

    It 'includes /p:_EnvLibraryPath=C:\Program Files\Lib (unquoted)' {
      $script:capturedArgs | Should -Contain '/p:_EnvLibraryPath=C:\Program Files\Lib'
    }

  }

  Context 'Property value containing semicolons is passed verbatim (unquoted)' {

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
        -Target      'Build' `
        -Verbosity   'normal' `
        -Property    @{ DCC_ResourcePath = 'C:\A;C:\B' }
    }

    It 'includes /p:DCC_ResourcePath=C:\A;C:\B (unquoted)' {
      $script:capturedArgs | Should -Contain '/p:DCC_ResourcePath=C:\A;C:\B'
    }

  }

  Context 'Property is appended after built-in properties (override precedence)' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      # An explicit Config via -Property must land AFTER the built-in /p:Config
      # so MSBuild's last-wins rule makes it override.
      Invoke-MsbuildProject `
        -ProjectFile 'C:\Projects\MyApp.dproj' `
        -Platform    'Win32' `
        -Config      'Debug' `
        -Target      'Build' `
        -Verbosity   'normal' `
        -Property    @{ Config = 'Release' }
    }

    It 'built-in /p:Config=Debug still present' {
      $script:capturedArgs | Should -Contain '/p:Config=Debug'
    }

    It 'override /p:Config=Release appears later in the argument list' {
      $builtinIdx  = [array]::IndexOf($script:capturedArgs, '/p:Config=Debug')
      $overrideIdx = [array]::IndexOf($script:capturedArgs, '/p:Config=Release')
      $overrideIdx | Should -BeGreaterThan $builtinIdx
    }

  }

  Context 'BuildAllUnits switch adds /p:DCC_BuildAllUnits=true' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile    'C:\Projects\MyApp.dproj' `
        -Platform       'Win32' `
        -Config         'Debug' `
        -Target         'Build' `
        -Verbosity      'normal' `
        -BuildAllUnits
    }

    It 'includes /p:DCC_BuildAllUnits=true' {
      $script:capturedArgs | Should -Contain '/p:DCC_BuildAllUnits=true'
    }

  }

  Context 'BuildAllUnits omitted adds no /p:DCC_BuildAllUnits argument' {

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
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'no argument contains DCC_BuildAllUnits' {
      ($script:capturedArgs | Where-Object { $_ -like '*DCC_BuildAllUnits*' }) | Should -BeNullOrEmpty
    }

  }

  Context 'EnvLibraryPath adds /p:_EnvLibraryPath (unquoted)' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile     'C:\Projects\MyApp.dproj' `
        -Platform        'Win32' `
        -Config          'Debug' `
        -Target          'Build' `
        -Verbosity       'normal' `
        -EnvLibraryPath  'C:\Program Files\Lib'
    }

    It 'includes /p:_EnvLibraryPath=C:\Program Files\Lib (unquoted)' {
      $script:capturedArgs | Should -Contain '/p:_EnvLibraryPath=C:\Program Files\Lib'
    }

  }

  Context 'EnvLibraryPath omitted adds no /p:_EnvLibraryPath argument' {

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
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'no argument contains _EnvLibraryPath' {
      ($script:capturedArgs | Where-Object { $_ -like '*_EnvLibraryPath*' }) | Should -BeNullOrEmpty
    }

  }

  Context 'EnvLibraryPath trailing backslash is trimmed' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile     'C:\Projects\MyApp.dproj' `
        -Platform        'Win32' `
        -Config          'Debug' `
        -Target          'Build' `
        -Verbosity       'normal' `
        -EnvLibraryPath  'C:\Lib\'
    }

    It 'includes /p:_EnvLibraryPath=C:\Lib (trailing separator removed)' {
      $script:capturedArgs | Should -Contain '/p:_EnvLibraryPath=C:\Lib'
    }

  }

  Context 'EnvLibraryPath drive-root separator is preserved' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile     'C:\Projects\MyApp.dproj' `
        -Platform        'Win32' `
        -Config          'Debug' `
        -Target          'Build' `
        -Verbosity       'normal' `
        -EnvLibraryPath  'C:\'
    }

    It 'includes /p:_EnvLibraryPath=C:\ (drive root kept)' {
      $script:capturedArgs | Should -Contain '/p:_EnvLibraryPath=C:\'
    }

  }

  Context 'UnitSearchPath trailing backslash on each entry is trimmed' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile    'C:\Projects\MyApp.dproj' `
        -Platform       'Win32' `
        -Config         'Debug' `
        -Target         'Build' `
        -Verbosity      'normal' `
        -UnitSearchPath @('C:\Libs\A\', 'C:\Libs\B\')
    }

    It 'includes /p:DCC_UnitSearchPath=$(DCC_UnitSearchPath);C:\Libs\A;C:\Libs\B (no trailing separators)' {
      $script:capturedArgs | Should -Contain '/p:DCC_UnitSearchPath=$(DCC_UnitSearchPath);C:\Libs\A;C:\Libs\B'
    }

  }

  Context 'BuildAllUnits remains overridable via -Property' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-MsbuildExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      # -BuildAllUnits emits =true; a -Property override must land AFTER it.
      Invoke-MsbuildProject `
        -ProjectFile    'C:\Projects\MyApp.dproj' `
        -Platform       'Win32' `
        -Config         'Debug' `
        -Target         'Build' `
        -Verbosity      'normal' `
        -BuildAllUnits `
        -Property       @{ DCC_BuildAllUnits = 'false' }
    }

    It 'first-class /p:DCC_BuildAllUnits=true still present' {
      $script:capturedArgs | Should -Contain '/p:DCC_BuildAllUnits=true'
    }

    It '-Property override /p:DCC_BuildAllUnits=false appears later' {
      $firstClassIdx = [array]::IndexOf($script:capturedArgs, '/p:DCC_BuildAllUnits=true')
      $overrideIdx   = [array]::IndexOf($script:capturedArgs, '/p:DCC_BuildAllUnits=false')
      $overrideIdx | Should -BeGreaterThan $firstClassIdx
    }

  }

  Context 'MsbuildPath is forwarded to Invoke-MsbuildExe' {

    BeforeAll {
      $script:capturedMsbuildPath = $null
      Mock Invoke-MsbuildExe {
        $script:capturedMsbuildPath = $MsbuildPath
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile 'C:\Projects\MyApp.dproj' `
        -Platform    'Win32' `
        -Config      'Debug' `
        -Target      'Build' `
        -Verbosity   'normal' `
        -MsbuildPath 'C:\NET\v4.0.30319\msbuild.exe'
    }

    It 'passes the MsbuildPath through to Invoke-MsbuildExe' {
      $script:capturedMsbuildPath | Should -Be 'C:\NET\v4.0.30319\msbuild.exe'
    }

  }

  Context 'MsbuildPath omitted forwards empty string to Invoke-MsbuildExe' {

    BeforeAll {
      $script:capturedMsbuildPath = 'sentinel'
      Mock Invoke-MsbuildExe {
        $script:capturedMsbuildPath = $MsbuildPath
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-MsbuildProject `
        -ProjectFile 'C:\Projects\MyApp.dproj' `
        -Platform    'Win32' `
        -Config      'Debug' `
        -Target      'Build' `
        -Verbosity   'normal'
    }

    It 'MsbuildPath is empty (Invoke-MsbuildExe falls back to PATH lookup)' {
      $script:capturedMsbuildPath | Should -BeNullOrEmpty
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

  Context 'accepts WinARM64EC before pre-MSBuild validation' {

    BeforeAll {
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dproj',
        '-Platform',    'WinARM64EC'
      )
    }

    It 'continues past parameter binding and exits 3 for missing rootDir' {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr contains the missing rootDir message' {
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

  Context 'exits 2 when -MsbuildPath does not exist' {

    BeforeAll {
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dproj',
        '-MsbuildPath', 'C:\DoesNotExist\v4.0.30319\msbuild.exe'
      )
    }

    It 'exit code is 2' {
      $script:result.ExitCode | Should -Be 2
    }

    It 'stderr mentions the missing MSBuild executable' {
      $script:result.StdErr -join ' ' | Should -Match 'MSBuild executable not found'
    }

  }

  Context 'exits 2 when -MsbuildPath is a directory (not a file)' {

    BeforeAll {
      # A directory exists on disk but is not an msbuild.exe.  Without -PathType
      # Leaf the Test-Path guard would accept it and fail later with a worse error.
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dproj',
        '-MsbuildPath', ([System.IO.Path]::GetTempPath())
      )
    }

    It 'exit code is 2' {
      $script:result.ExitCode | Should -Be 2
    }

    It 'stderr mentions the missing MSBuild executable' {
      $script:result.StdErr -join ' ' | Should -Match 'MSBuild executable not found'
    }

  }

  Context '-SkipRsvars bypasses the rootDir/rsvars requirement' {

    BeforeAll {
      # No -RootDir supplied.  Without -SkipRsvars this would exit 3; with it,
      # rootDir/rsvars validation is skipped and the flow reaches the project
      # file check, which fails (exit 4) for a non-existent project.  This
      # proves -SkipRsvars removes the rsvars requirement while leaving later
      # validation intact.
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\DoesNotExist.dproj',
        '-SkipRsvars'
      )
    }

    It 'does not exit 3 (rootDir/rsvars no longer required)' {
      $script:result.ExitCode | Should -Not -Be 3
    }

    It 'exit code is 4 (project validation still runs)' {
      $script:result.ExitCode | Should -Be 4
    }

    It 'stderr does not mention rsvars.bat' {
      $script:result.StdErr -join ' ' | Should -Not -Match 'rsvars\.bat'
    }

  }

}

Describe 'Get-PathWithoutTrailingSeparator' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-MsBuildScriptPath)
  }

  It 'trims a single trailing backslash' {
    Get-PathWithoutTrailingSeparator 'C:\Lib\' | Should -Be 'C:\Lib'
  }

  It 'trims multiple trailing backslashes' {
    Get-PathWithoutTrailingSeparator 'C:\Lib\\' | Should -Be 'C:\Lib'
  }

  It 'leaves a value with no trailing separator unchanged' {
    Get-PathWithoutTrailingSeparator 'C:\Lib' | Should -Be 'C:\Lib'
  }

  It 'preserves a drive-root separator' {
    Get-PathWithoutTrailingSeparator 'C:\' | Should -Be 'C:\'
  }

  It 'returns an empty string unchanged' {
    Get-PathWithoutTrailingSeparator '' | Should -Be ''
  }

  It 'returns an all-separator value unchanged' {
    Get-PathWithoutTrailingSeparator '\\' | Should -Be '\\'
  }

}

Describe 'Test-NativeQuotingRisk' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-MsBuildScriptPath)
  }

  It 'flags a value with a space and a trailing backslash' {
    Test-NativeQuotingRisk 'C:\Program Files\Lib\' | Should -BeTrue
  }

  It 'flags a value with a space and multiple trailing backslashes' {
    Test-NativeQuotingRisk 'C:\Program Files\Lib\\' | Should -BeTrue
  }

  It 'does not flag a trailing backslash without whitespace' {
    Test-NativeQuotingRisk 'C:\Lib\' | Should -BeFalse
  }

  It 'does not flag whitespace without a trailing backslash' {
    Test-NativeQuotingRisk 'C:\Program Files\Lib' | Should -BeFalse
  }

  It 'does not flag a plain value' {
    Test-NativeQuotingRisk 'DEBUG;CI' | Should -BeFalse
  }

}

Describe 'Native argument passing (real arg-echo exe)' {

  # Compile a tiny native console app that prints each argv element on its own
  # line, prefixed 'ARG:'.  This exercises the real PowerShell-array -> command
  # line -> CommandLineToArgvW -> child-argv path that Invoke-MsbuildExe uses, so
  # a value ending in a backslash (or containing a space) is verified end-to-end
  # rather than by asserting the shape of the argument string.
  #
  # Requires the .NET Framework C# compiler (csc.exe); on machines/CI without it
  # (e.g. Linux runners) every test here skips.  Evaluated at Pester discovery
  # time so -Skip: can capture it.
  $frameworkRoots = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
  )
  $cscDiscover  = if ($env:WINDIR) { $frameworkRoots | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 } else { $null }
  $skipNative   = -not $cscDiscover

  # Windows PowerShell 5.1, located via its fixed path (see WindowsPS51Compat.Tests.ps1).
  $ps51Discover = if ($env:SystemRoot) {
    [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  } else { $null }
  $skipPs51 = $skipNative -or -not ($ps51Discover -and (Test-Path -LiteralPath $ps51Discover))

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-MsBuildScriptPath)
    $script:scriptPath = Get-MsBuildScriptPath

    $script:csc = $null
    if ($env:WINDIR) {
      $script:csc = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
      ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }

    $script:winPS51Exe = $null
    if ($env:SystemRoot) {
      $candidate = [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
      if (Test-Path -LiteralPath $candidate) { $script:winPS51Exe = $candidate }
    }

    $script:workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dmb-native-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:workDir -Force

    $script:argEchoExe = $null
    if ($script:csc) {
      $src = Join-Path $script:workDir 'ArgEcho.cs'
      $exe = Join-Path $script:workDir 'ArgEcho.exe'
      $code = @'
using System;
class ArgEcho {
  static int Main(string[] args) {
    foreach (var a in args) { Console.Out.WriteLine("ARG:" + a); }
    return 0;
  }
}
'@
      Set-Content -LiteralPath $src -Value $code -Encoding UTF8
      & $script:csc /nologo "/out:$exe" $src | Out-Null
      if (Test-Path -LiteralPath $exe) { $script:argEchoExe = $exe }
    }

    # A real project file on disk so the top-level script passes its Test-Path
    # check (used by the PS 5.1 end-to-end case).
    $script:dummyProj = Join-Path $script:workDir 'MyApp.dproj'
    Set-Content -LiteralPath $script:dummyProj -Value '<Project/>' -Encoding UTF8

    # Helper: extract the 'ARG:'-prefixed lines emitted by the arg-echo exe.
    function script:Get-EchoedArgs {
      param([string]$Text)
      return @(($Text -split "`r?`n") | Where-Object { $_ -like 'ARG:*' } | ForEach-Object { $_.Substring(4) })
    }
  }

  AfterAll {
    if ($script:workDir -and (Test-Path -LiteralPath $script:workDir)) {
      Remove-Item -LiteralPath $script:workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Context 'PowerShell 7 host: value with a space and trailing backslash reaches the child intact' {

    BeforeAll {
      if (-not $script:argEchoExe) { return }
      # EnvLibraryPath value has BOTH a space and a trailing backslash -- the worst
      # case for the old hand-quoting.  The trailing separator is trimmed; the
      # remaining value must arrive as a single argv element, quotes and boundary
      # intact, with the following built-in arguments preserved separately.
      $r = Invoke-MsbuildProject `
        -ProjectFile    $script:dummyProj `
        -Platform       'Win32' `
        -Config         'Release' `
        -Target         'Build' `
        -Verbosity      'minimal' `
        -MsbuildPath    $script:argEchoExe `
        -EnvLibraryPath 'C:\Program Files\Lib\'
      $script:received = script:Get-EchoedArgs -Text $r.Output
    }

    It 'delivers /p:_EnvLibraryPath=C:\Program Files\Lib as one intact argument' -Skip:$skipNative {
      $script:received | Should -Contain '/p:_EnvLibraryPath=C:\Program Files\Lib'
    }

    It 'preserves the following /p:Platform=Win32 as a separate argument' -Skip:$skipNative {
      $script:received | Should -Contain '/p:Platform=Win32'
    }

    It 'no delivered argument contains a stray double quote' -Skip:$skipNative {
      ($script:received | Where-Object { $_ -like '*"*' }) | Should -BeNullOrEmpty
    }

  }

  Context 'Windows PowerShell 5.1 host: end-to-end script delivers the value intact' {

    BeforeAll {
      if (-not $script:argEchoExe -or -not $script:winPS51Exe) { return }
      # Run the whole script under powershell.exe (5.1) with the arg-echo as the
      # msbuild binary.  Invoke-MsbuildExe's `& $exe @Arguments` is then built by
      # 5.1's own native-argument quoting -- the real target of the regression.
      $script:ps51Result = Invoke-ToolProcess `
        -Shell           $script:winPS51Exe `
        -ExecutionPolicy 'Bypass' `
        -ScriptPath      $script:scriptPath `
        -Arguments       @(
          '-ProjectFile', $script:dummyProj,
          '-SkipRsvars',
          '-MsbuildPath', $script:argEchoExe,
          '-Platform', 'Win32',
          '-Config', 'Release',
          '-EnvLibraryPath', 'C:\Program Files\Lib\',
          '-Format', 'json'
        )
      $jsonLine = $script:ps51Result.StdOut | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1
      $obj = if ($jsonLine) { $jsonLine | ConvertFrom-Json } else { $null }
      $script:ps51Received = if ($obj) { script:Get-EchoedArgs -Text $obj.output } else { @() }
    }

    It 'script exits 0 (arg-echo returns 0)' -Skip:$skipPs51 {
      $script:ps51Result.ExitCode | Should -Be 0
    }

    It 'delivers /p:_EnvLibraryPath=C:\Program Files\Lib as one intact argument' -Skip:$skipPs51 {
      $script:ps51Received | Should -Contain '/p:_EnvLibraryPath=C:\Program Files\Lib'
    }

    It 'preserves the following /p:Platform=Win32 as a separate argument' -Skip:$skipPs51 {
      $script:ps51Received | Should -Contain '/p:Platform=Win32'
    }

  }

  Context 'Windows PowerShell 5.1 host: warns on an unquotable -Property value' {

    BeforeAll {
      if (-not $script:argEchoExe -or -not $script:winPS51Exe) { return }
      # A generic -Property value with BOTH a space and a trailing backslash is the
      # one case the fix cannot make safe on PS 5.1 (its own native quoting escapes
      # the closing quote).  The script must emit a clear warning naming the property
      # rather than silently corrupting the argument.
      #
      # -Property is a [hashtable] parameter, which cannot bind from a plain -File
      # string argument, so invoke via an EncodedCommand that dot-sources the script
      # (the InvocationName='.' guard returns after defining the functions) and calls
      # Invoke-MsbuildProject with a real hashtable.  Single-quoted PowerShell string
      # literals carry the trailing backslash safely into the call; the hazard under
      # test is the *native* command line msbuild.exe receives, not this literal.
      $inner = ". '$($script:scriptPath)'; " +
               "Invoke-MsbuildProject -ProjectFile '$($script:dummyProj)' -Platform Win32 -Config Release " +
               "-Target Build -Verbosity minimal -MsbuildPath '$($script:argEchoExe)' " +
               "-Property @{ DCC_ResourcePath = 'C:\Program Files\Res\' } | Out-Null"
      $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($inner))

      $psi = [System.Diagnostics.ProcessStartInfo]::new()
      $psi.FileName = $script:winPS51Exe
      foreach ($a in @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)) {
        [void]$psi.ArgumentList.Add($a)
      }
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError  = $true
      $psi.UseShellExecute        = $false

      $p = [System.Diagnostics.Process]::new()
      $p.StartInfo = $psi
      [void]$p.Start()
      $errTask = $p.StandardError.ReadToEndAsync()
      $null = $p.StandardOutput.ReadToEndAsync()
      $p.WaitForExit()
      $script:ps51WarnText = $errTask.GetAwaiter().GetResult()
    }

    It 'emits a warning naming the property and the backslash hazard' -Skip:$skipPs51 {
      $script:ps51WarnText | Should -Match 'DCC_ResourcePath'
      $script:ps51WarnText | Should -Match 'backslash'
    }

  }

}
