<#
delphi-msbuild.ps1

Build a Delphi project using MSBuild.

Sources the Delphi build environment from rsvars.bat found under <RootDir>\bin\.
Designed to be run stand-alone or to accept piped output from
delphi-inspect.ps1 -DetectLatest -BuildSystem MSBuild.

USAGE
  # Auto-discover latest Delphi and build
  delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
      delphi-msbuild.ps1 -ProjectFile MyApp.dproj

  # Explicit root dir
  delphi-msbuild.ps1 -ProjectFile MyApp.dproj -RootDir "C:\RAD\Studio\23.0"

  # Override platform / config
  delphi-inspect.ps1 -DetectLatest -Platform Win64 -BuildSystem MSBuild |
      delphi-msbuild.ps1 -ProjectFile MyApp.dproj -Platform Win64 -Config Release

  # Stream output and rebuild
  delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
      delphi-msbuild.ps1 -ProjectFile MyApp.dproj -Target Rebuild -ShowOutput

NOTES
  -RootDir is the Delphi installation root (e.g. C:\RAD\Studio\23.0).
  rsvars.bat is expected at <RootDir>\bin\rsvars.bat.

  When piped a delphi-inspect result object, RootDir is taken from the object's
  .rootDir property.  An explicit -RootDir parameter takes precedence.

  -Config is the RAD Studio MSBuild property name (/p:Config); common values
  are Debug and Release.

  MSBuild output is always captured and returned in the result object's
  .output property.  Use -ShowOutput to also stream output to the console in
  real time; .output is populated in both cases.

  Exit codes:
    0  success
    1  unexpected error
    2  reserved (invalid arguments)
    3  rootDir missing/empty, directory not found, or rsvars.bat not found
    4  project file not found
    5  MSBuild failed (non-zero exit code)
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ExitInvalidArguments',
  Justification='Reserved exit code constant; not yet referenced in code paths')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '',
  Justification='Script accepts at most one piped installation object; end-block semantics are correct.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Get-RsvarsEnvLines',
  Justification='Function returns multiple KEY=VALUE lines from cmd.exe set; plural noun is accurate.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
  Justification='Write-Host is intentional: -ShowOutput streams build text directly to the console host.')]
param(
  [Parameter(ValueFromPipeline=$true)]
  [psobject]$DelphiInstallation,

  [Parameter(Position=0)]
  [string]$ProjectFile,

  [string]$RootDir,

  [ValidateSet('Win32','Win64','macOS32','macOS64','macOSARM64','Linux64',
               'iOS32','iOSSimulator32','iOS64','iOSSimulator64','Android32','Android64','WinARM64EC')]
  [string]$Platform = 'Win32',

  [string]$Config = 'Debug',

  [ValidateSet('Build','Clean','Rebuild')]
  [string]$Target = 'Build',

  [ValidateSet('quiet','minimal','normal','detailed','diagnostic')]
  [string]$Verbosity = 'normal',

  # Output directory for the compiled executable or DLL (/p:DCC_ExeOutput property).
  [string]$ExeOutputDir,

  # Output directory for compiled DCU files (/p:DCC_DcuOutput property).
  [string]$DcuOutputDir,

  # Additional unit search paths (/p:DCC_UnitSearchPath property).  Multiple paths are
  # joined with semicolons and appended to the paths already set by the project's
  # PropertyGroups.
  [string[]]$UnitSearchPath = @(),

  [string[]]$Define = @(),

  [switch]$ShowOutput,

  # When set, the result object is written as compressed JSON to this file path.
  # Used by Invoke-BuildPipeline to capture structured results from the subprocess
  # while still streaming build output to the console via | Out-Host.
  [string]$OutputFile,

  # Output format for the result object.
  # object (default) -- emits a PSCustomObject to the pipeline.
  # json             -- emits a single compressed JSON line; used by Invoke-BuildPipeline
  #                     to capture structured results from the subprocess.
  [ValidateSet('object', 'json')]
  [string]$Format = 'object'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExitSuccess          = 0
$ExitUnexpectedError  = 1
$ExitInvalidArguments = 2
$ExitRootDirError     = 3
$ExitProjectNotFound  = 4
$ExitBuildFailed      = 5

$script:Version = '0.7.0'
$ToolVersion = $script:Version

# BEGIN-CD-HOSTLOG
# -----------------------------------------------------------------------------
# Write-CDHostLog v0.1.0
# Source: https://github.com/continuous-delphi/delphi-logger
#
# Universal output function for Continuous-Delphi PowerShell tooling.
# Opt-in structured logging via ContinuousDelphi.Logger module.
# See: https://github.com/continuous-delphi/delphi-logger/docs/output-modes.md
# -----------------------------------------------------------------------------

# Logger detection -- check once at load time whether the caller has loaded
# ContinuousDelphi.Logger. If so, structured events are emitted alongside
# native PowerShell stream output. If not, Write-CDHostLog routes to native
# Write-Output / Write-Verbose / Write-Host / Write-Warning / Write-Error only.
$script:LoggerAvailable = [bool](Get-Module -Name 'ContinuousDelphi.Logger')
$script:LoggerCaptureOutput = if ($script:LoggerAvailable) {
  $script:CDLoggerState = (Get-Module -Name 'ContinuousDelphi.Logger').SessionState.PSVariable.GetValue('CDLoggerState')
  if ($null -ne $script:CDLoggerState) { $script:CDLoggerState.CaptureOutput } else { $false }
} else { $false }

function Write-CDHostLog {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification='Write-Host is used intentionally for Info/Success level output to stream 6 without polluting the pipeline')]
  param(
    [Parameter(Mandatory)]
    $Message,

    [ValidateSet('Output','Trace','Debug','Verbose','Info','Success','Warning','Error','Fatal')]
    [string]$Level = 'Info',

    [string]$EventId,
    [hashtable]$Data,

    [switch]$LogOnly
  )

  # Write to native PowerShell stream (unless LogOnly)
  if (-not $LogOnly) {
    switch ($Level) {
      'Output' {
        Write-Output $Message
      }
      { $_ -in 'Trace','Debug','Verbose' } {
        Write-Verbose $Message
      }
      { $_ -in 'Info','Success' } {
        Write-Host $Message
      }
      'Warning' {
        Write-Warning $Message
      }
      { $_ -in 'Error','Fatal' } {
        Write-Error $Message -ErrorAction Continue
      }
    }
  }

  # Also emit structured log event if logger available
  if ($script:LoggerAvailable) {
    $msgStr = [string]$Message
    if ([string]::IsNullOrWhiteSpace($msgStr)) { return }
    if ($Level -eq 'Output') {
      if (-not $script:LoggerCaptureOutput) { return }
      $logLevel = 'Info'
    } else {
      $logLevel = $Level
    }
    $params = @{ Level = $logLevel; Message = $msgStr }
    if ($EventId) { $params.EventId = $EventId }
    if ($Data)    { $params.Data = $Data }
    Write-CDLogEvent @params
  }
}

function Complete-CDActivity {
  param(
    [int]$ExitCode,
    [string]$Command,
    [string]$Message
  )
  if (-not $script:LoggerAvailable) { return }
  $result = New-CDActivityResult `
    -ToolVersion $ToolVersion `
    -Activity $Command `
    -ExitCode $ExitCode `
    -Message $Message
  Write-Information -MessageData $result -Tags @('CDLog', 'ActivityResult')
}
# END-CD-HOSTLOG

# Resolve the Delphi root dir from the explicit -RootDir parameter or from a
# piped delphi-inspect result object (.rootDir property).
# Returns $null when neither source provides a value.
function Resolve-RootDir {
  param(
    [string]$ExplicitRootDir,
    [psobject]$Installation
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRootDir)) {
    return $ExplicitRootDir
  }

  if ($null -ne $Installation) {
    $prop = $Installation.PSObject.Properties['rootDir']
    if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
      return [string]$prop.Value
    }
  }

  return $null
}

# Derive the expected rsvars.bat path from the Delphi root dir.
function Get-RsvarsPath {
  param([string]$RootDir)
  return Join-Path (Join-Path $RootDir 'bin') 'rsvars.bat'
}

# Invoke cmd.exe to source rsvars.bat and capture the resulting environment.
# Returns the raw KEY=VALUE lines from `set`.
# Separated into its own function so tests can mock it.
function Get-RsvarsEnvLines {
  param([string]$RsvarsPath)
  $lines = @(& cmd.exe /c "call `"$RsvarsPath`" > nul 2>&1 && set")
  if ($LASTEXITCODE -ne 0) {
    throw "rsvars.bat exited with code $LASTEXITCODE : $RsvarsPath"
  }
  return $lines
}

# Source rsvars.bat into the current process environment.
# Calls Get-RsvarsEnvLines (mockable) and applies each KEY=VALUE pair.
function Invoke-RsvarsEnvironment {
  param([string]$RsvarsPath)

  $lines = Get-RsvarsEnvLines -RsvarsPath $RsvarsPath
  $count = 0
  foreach ($line in $lines) {
    if ($line -match '^([^=]+)=(.*)$') {
      [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
      $count++
    }
  }

  if ($count -eq 0) {
    throw "rsvars.bat produced no environment variables -- check that rsvars.bat is valid: $RsvarsPath"
  }
}

# Invoke msbuild.exe with the given arguments.
# Returns [pscustomobject]@{ ExitCode; Output } where Output is always the
# captured build text.  When -ShowOutput is set each output line is also
# written to the host as MSBuild emits it.
# Separated into its own function so tests can mock it.
function Invoke-MsbuildExe {
  param(
    [string[]]$Arguments,
    [switch]$ShowOutput
  )

  $outputLines = New-Object System.Collections.Generic.List[string]
  & msbuild.exe @Arguments 2>&1 | ForEach-Object {
    $line = [string]$_
    [void]$outputLines.Add($line)
    if ($ShowOutput) { Write-CDHostLog -Level Info -Message $line }
  }
  $exitCode = $LASTEXITCODE
  $output = $outputLines -join [Environment]::NewLine
  if ($outputLines.Count -gt 0) {
    $output += [Environment]::NewLine
  }
  return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

# Assemble MSBuild arguments and invoke the build.
# Returns the result object from Invoke-MsbuildExe.
function Invoke-MsbuildProject {
  param(
    [string]$ProjectFile,
    [string]$Platform,
    [string]$Config,
    [string]$Target,
    [string]$Verbosity,
    [string]$ExeOutputDir,
    [string]$DcuOutputDir,
    [string[]]$UnitSearchPath = @(),
    [string[]]$Define         = @(),
    [switch]$ShowOutput
  )

  $msbuildArgs = @(
    $ProjectFile,
    "/t:$Target",
    "/p:Config=$Config",
    "/p:Platform=$Platform",
    "/nologo",
    "/v:$Verbosity"
  )

  if (-not [string]::IsNullOrWhiteSpace($ExeOutputDir)) { $msbuildArgs += "/p:DCC_ExeOutput=$ExeOutputDir" }
  if (-not [string]::IsNullOrWhiteSpace($DcuOutputDir)) { $msbuildArgs += "/p:DCC_DcuOutput=$DcuOutputDir" }

  if ($UnitSearchPath.Count -gt 0) {
    $unitSearchValue = '$(DCC_UnitSearchPath);' + ($UnitSearchPath -join ';')
    $msbuildArgs += "/p:DCC_UnitSearchPath=`"$unitSearchValue`""
  }

  if ($Define.Count -gt 0) {
    $defineValue = '$(DCC_Define);' + ($Define -join ';')
    $msbuildArgs += "/p:DCC_Define=`"$defineValue`""
  }

  return Invoke-MsbuildExe -Arguments $msbuildArgs -ShowOutput:$ShowOutput
}

# Parse the dcc32.exe invocation line from captured msbuild output and extract
# the exe output dir (-E flag) and DCU output dir (-NO flag).
# Paths are resolved to absolute using the project file directory as base.
# Returns [pscustomobject]@{ ExeOutputDir; DcuOutputDir } -- either may be $null.
function Get-BuildOutputDir {
  param(
    [string]$Output,
    [string]$ProjectFileDir
  )

  $result = [pscustomobject]@{ ExeOutputDir = $null; DcuOutputDir = $null }
  if ([string]::IsNullOrWhiteSpace($Output)) { return $result }

  $dcc32Line = ($Output -split "`n") |
    Where-Object { $_ -match '[/\\]dcc32\.exe\s' } |
    Select-Object -First 1
  if (-not $dcc32Line) { return $result }

  if ($dcc32Line -match '\s-E(\S+)') {
    $result.ExeOutputDir = [System.IO.Path]::GetFullPath(
      [System.IO.Path]::Combine($ProjectFileDir, $Matches[1]))
  }

  if ($dcc32Line -match '\s-NO(\S+)') {
    $result.DcuOutputDir = [System.IO.Path]::GetFullPath(
      [System.IO.Path]::Combine($ProjectFileDir, $Matches[1]))
  }

  return $result
}

# Parse the MSBuild summary block from captured output and return warning and
# error counts as integers.
# Returns [pscustomobject]@{ Warnings; Errors }.
function Get-BuildCount {
  param([string]$Output)

  $warnings = 0
  $errors   = 0
  if (-not [string]::IsNullOrWhiteSpace($Output)) {
    $wMatch = [regex]::Match($Output, '^\s*(\d+)\s+Warning\(s\)',
      [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $eMatch = [regex]::Match($Output, '^\s*(\d+)\s+Error\(s\)',
      [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($wMatch.Success) { $warnings = [int]$wMatch.Groups[1].Value }
    if ($eMatch.Success) { $errors   = [int]$eMatch.Groups[1].Value }
  }
  return [pscustomobject]@{ Warnings = $warnings; Errors = $errors }
}

# Guard: skip top-level execution when the script is dot-sourced for testing.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
  if ([string]::IsNullOrWhiteSpace($ProjectFile)) {
    Write-CDHostLog -Level Error -Message '-ProjectFile is required.' -EventId 'INVALID-ARGS'
    Complete-CDActivity -ExitCode $ExitInvalidArguments -Command 'build' -Message 'ProjectFile is required'
    exit $ExitInvalidArguments
  }

  $resolvedRootDir = Resolve-RootDir -ExplicitRootDir $RootDir -Installation $DelphiInstallation
  Write-CDHostLog -Level Verbose -Message "Project: $ProjectFile, Platform: $Platform, Config: $Config, Target: $Target"

  if ([string]::IsNullOrWhiteSpace($resolvedRootDir)) {
    $msg = 'No Delphi root dir supplied. Provide -RootDir or pipe a delphi-inspect result object.'
    Write-CDHostLog -Level Error -Message $msg -EventId 'ROOTDIR-MISSING'
    Complete-CDActivity -ExitCode $ExitRootDirError -Command 'build' -Message $msg
    exit $ExitRootDirError
  }

  Write-CDHostLog -Level Verbose -Message "RootDir: $resolvedRootDir"

  if (-not (Test-Path -LiteralPath $resolvedRootDir)) {
    $msg = "Delphi root dir not found on disk: $resolvedRootDir"
    Write-CDHostLog -Level Error -Message $msg -EventId 'ROOTDIR-NOT-FOUND'
    Complete-CDActivity -ExitCode $ExitRootDirError -Command 'build' -Message $msg
    exit $ExitRootDirError
  }

  $rsvarsPath = Get-RsvarsPath -RootDir $resolvedRootDir
  if (-not (Test-Path -LiteralPath $rsvarsPath)) {
    $msg = "rsvars.bat not found: $rsvarsPath"
    Write-CDHostLog -Level Error -Message $msg -EventId 'RSVARS-NOT-FOUND'
    Complete-CDActivity -ExitCode $ExitRootDirError -Command 'build' -Message $msg
    exit $ExitRootDirError
  }

  Write-CDHostLog -Level Verbose -Message "rsvars.bat: $rsvarsPath"

  $resolvedProjectFile = [System.IO.Path]::GetFullPath($ProjectFile)
  if (-not (Test-Path -LiteralPath $resolvedProjectFile)) {
    $msg = "Project file not found: $resolvedProjectFile"
    Write-CDHostLog -Level Error -Message $msg -EventId 'PROJECT-NOT-FOUND'
    Complete-CDActivity -ExitCode $ExitProjectNotFound -Command 'build' -Message $msg
    exit $ExitProjectNotFound
  }

  Invoke-RsvarsEnvironment -RsvarsPath $rsvarsPath

  $buildResult = Invoke-MsbuildProject `
    -ProjectFile   $resolvedProjectFile `
    -Platform      $Platform `
    -Config        $Config `
    -Target        $Target `
    -Verbosity     $Verbosity `
    -ExeOutputDir  $ExeOutputDir `
    -DcuOutputDir  $DcuOutputDir `
    -UnitSearchPath $UnitSearchPath `
    -Define        $Define `
    -ShowOutput:$ShowOutput

  $parsedDirs = Get-BuildOutputDir `
    -Output         $buildResult.Output `
    -ProjectFileDir (Split-Path $resolvedProjectFile -Parent)
  $counts = Get-BuildCount -Output $buildResult.Output

  $resultObj = [pscustomobject]@{
    output         = $buildResult.Output
    scriptVersion  = $script:Version
    projectFile    = $resolvedProjectFile
    platform       = $Platform
    config         = $Config
    target         = $Target
    define         = $Define
    rootDir        = $resolvedRootDir
    rsvarsPath     = $rsvarsPath
    exeOutputDir   = if (-not [string]::IsNullOrWhiteSpace($ExeOutputDir)) { $ExeOutputDir } else { $parsedDirs.ExeOutputDir }
    dcuOutputDir   = if (-not [string]::IsNullOrWhiteSpace($DcuOutputDir)) { $DcuOutputDir } else { $parsedDirs.DcuOutputDir }
    unitSearchPath = if ($UnitSearchPath.Count -eq 0) { $null } else { $UnitSearchPath }
    exitCode       = $buildResult.ExitCode
    success        = ($buildResult.ExitCode -eq 0)
    warnings       = $counts.Warnings
    errors         = $counts.Errors
  }

  if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    Set-Content -LiteralPath $OutputFile -Value ($resultObj | ConvertTo-Json -Depth 5 -Compress) -Encoding UTF8
  }

  if ($Format -eq 'json') {
    Write-CDHostLog -Level Output -Message ($resultObj | ConvertTo-Json -Depth 5 -Compress)
  } else {
    Write-CDHostLog -Level Output -Message $resultObj
  }

  if ($buildResult.ExitCode -ne 0) {
    Write-CDHostLog -Level Error -Message "MSBuild failed with exit code $($buildResult.ExitCode)" -EventId 'BUILD-FAILED' `
      -Data @{ exitCode = $buildResult.ExitCode; warnings = $counts.Warnings; errors = $counts.Errors }
    Complete-CDActivity -ExitCode $ExitBuildFailed -Command 'build' -Message "MSBuild failed with exit code $($buildResult.ExitCode)"
    exit $ExitBuildFailed
  }

  Write-CDHostLog -Level Verbose -Message "Build succeeded: $($counts.Warnings) warning(s), $($counts.Errors) error(s)"
  Complete-CDActivity -ExitCode $ExitSuccess -Command 'build'
  exit $ExitSuccess

} catch {
  $errMsg = if ([string]::IsNullOrWhiteSpace($_.Exception.Message)) { $_.ToString() } else { $_.Exception.Message }
  if ([string]::IsNullOrWhiteSpace($errMsg)) { $errMsg = 'Unknown error' }
  Write-CDHostLog -Level Fatal -Message $errMsg -EventId 'UNEXPECTED-ERROR'
  Complete-CDActivity -ExitCode $ExitUnexpectedError -Command 'build' -Message $errMsg
  exit $ExitUnexpectedError
}
