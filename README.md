# Overview

`delphi-msbuild.ps1` builds a Delphi `.dproj` project using
MSBuild.  It sources the Delphi build environment from `rsvars.bat`
(located under the Delphi installation root) and then invokes MSBuild
with the requested project file, platform, and configuration.

# Usage

```powershell
pwsh delphi-msbuild.ps1 -ProjectFile <path> [options]
```

------------------------------------------------------------------------

It is designed to be run stand-alone (using an explicit `-RootDir`
parameter) or to pipe the output of `delphi-inspect.ps1` which will
supply the installation root, such as:

```powershell
delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
      delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj
```

# Parameters

## -ProjectFile

```text
-ProjectFile <path>
```

Path to the `.dproj` project file.  **Required**.

The path is resolved to an absolute path before being passed to MSBuild.

## -RootDir

```text
-RootDir <path>
```

The Delphi installation root directory
(e.g. `C:\Program Files (x86)\Embarcadero\Studio\23.0`).

`rsvars.bat` is expected at `<RootDir>\bin\rsvars.bat`.

If omitted, `-RootDir` is taken from the `.rootDir` property of a
piped `delphi-inspect` result object.

Note: An explicit `-RootDir` takes precedence over the piped value.

## -Platform

```text
-Platform <platform>    (default: Win32)
```

The target compilation platform.  Passed to MSBuild as
`/p:Platform=<value>`.

Valid values:

- `Win32`
- `Win64`
- `macOS32`
- `macOS64`
- `macOSARM64`
- `Linux64`
- `iOS32`
- `iOSSimulator32`
- `iOS64`
- `iOSSimulator64`
- `Android32`
- `Android64`

## -Config

```text
-Config <value>    (default: Debug)
```

The build configuration name.  Passed to MSBuild as `/p:Config=<value>`.

Note: Common values are `Debug` and `Release`.

## -Target

```text
-Target <value>    (default: Build)
```

The MSBuild target to execute.

Valid values: `Build`, `Clean`, `Rebuild`

## -Verbosity

```text
-Verbosity <value>    (default: normal)
```

The MSBuild verbosity level.  Passed to MSBuild as `/v:<value>`.

Valid values: `quiet`, `minimal`, `normal`, `detailed`, `diagnostic`

## -ShowOutput   (switch)

```text
-ShowOutput
```

When set (meant for non-object pipeline usage)

- MSBuild output streams directly to stdout in real time.
- The result object's `.output` property is `null`.
- On build failure, a `Write-Error` message is emitted to stderr.

When not set (default):

- MSBuild output (stdout and stderr combined) is captured.
- The result object's `.output` property contains the full captured text.
- On build failure, no additional stderr message is emitted
  (the captured output already contains the compiler diagnostics).

## -DelphiInstallation (pipeline input)

```text
[psobject] (ValueFromPipeline)
```

Accepts a `pscustomobject` from `delphi-inspect.ps1 -DetectLatest`.
The `.rootDir` property is used as the Delphi installation root when
`-RootDir` is not supplied explicitly.

Note: Any object with a `.rootDir` string property is accepted; it
does not have to originate from `delphi-inspect.ps1`.

------------------------------------------------------------------------

# Result Object

On success or build failure (exit codes 0 and 5), a single
`pscustomobject` is written to the pipeline before the script exits.
This allows downstream pipeline steps to consume the build result.

| Property      | Type    | Description                                          |
|---------------|---------|------------------------------------------------------|
| `projectFile` | string  | Absolute path to the project file                    |
| `platform`    | string  | Platform value used (e.g. `Win32`)                   |
| `config`      | string  | Config value used (e.g. `Debug`)                     |
| `target`      | string  | Target used (e.g. `Build`)                           |
| `rootDir`     | string  | Resolved Delphi installation root                    |
| `rsvarsPath`  | string  | Derived path to `rsvars.bat`                         |
| `exitCode`    | int     | MSBuild process exit code                            |
| `success`     | bool    | `$true` when `exitCode` is 0                         |
| `output`      | string  | Captured MSBuild output; `$null` when `-ShowOutput`  |

Note: On fata errors before MSBuild is invoked (exit codes 2, 3, 4) no result
object is emitted.

------------------------------------------------------------------------

# Exit Codes

| Code | Meaning                                                             |
|------|---------------------------------------------------------------------|
| `0`  | Build succeeded                                                     |
| `1`  | Unexpected internal error (unhandled exception)                     |
| `2`  | `-ProjectFile` was not supplied                                     |
| `3`  | `rootDir` missing/empty, directory not found, or `rsvars.bat` absent|
| `4`  | Project file not found on disk                                      |
| `5`  | MSBuild completed but returned a non-zero exit code                 |

------------------------------------------------------------------------

## Example 1) Normal -- pipe from delphi-inspect and build

Discover the latest ready MSBuild installation and pipe it into a build:

```powershell
$result = delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
              delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj

$result.success    # $true
$result.exitCode   # 0
$result.platform   # Win32
$result.config     # Debug
$result.rootDir    # C:\Program Files (x86)\Embarcadero\Studio\23.0
$result.rsvarsPath # C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat
```

The captured MSBuild output is available in `$result.output` for
post-processing or logging.

## Example 2) Normal -- explicit root dir, Release config

Build without inspect, targeting a specific installation:

```powershell
$result = delphi-msbuild.ps1 `
              -ProjectFile  .\src\MyApp.dproj `
              -RootDir      'C:\Program Files (x86)\Embarcadero\Studio\23.0' `
              -Platform     Win64 `
              -Config       Release `
              -Verbosity    minimal
```

## Example 3) Normal -- stream output to console

Use `-ShowOutput` when you want build output visible in real time (e.g.
in a terminal session rather than a CI log capture):

```powershell
delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
  delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj -ShowOutput
```

MSBuild output appears on stdout as it runs.  `$result.output` is
`$null` in this mode.

## Example 4) Normal -- feed result into a downstream step

Because the result object is always written to the pipeline before exit,
you can chain a test runner or other step:

    $buildResult = delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
                       delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj

    if ($buildResult.success) {
        # run tests, package, etc.
    }

## Example 5) Error -- no Delphi installation supplied (exit 3)

Running without a piped object or `-RootDir`:

```powershell
delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj

# stderr: No Delphi root dir supplied. Provide -RootDir or pipe a
#         delphi-inspect result object.
# exit code: 3
# no result object emitted
```

The same exit code (3) is returned if `-RootDir` is supplied but the
directory does not exist on disk, or if `rsvars.bat` is absent under
`<RootDir>\bin\`:

```powershell
delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj -RootDir C:\Missing\Path

# stderr: Delphi root dir not found on disk: C:\Missing\Path
# exit code: 3

delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj -RootDir C:\SomeDir

# stderr: rsvars.bat not found: C:\SomeDir\bin\rsvars.bat
# exit code: 3
```

## Example 6) Error -- project file not found (exit 4)

```powershell
delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
    delphi-msbuild.ps1 -ProjectFile .\src\Typo.dproj

# stderr: Project file not found: C:\Work\src\Typo.dproj
# exit code: 4
# no result object emitted
```

## Example 7) Error -- MSBuild build failure (exit 5)

When MSBuild itself runs but returns a non-zero exit code (compilation
errors, missing components, etc.), the result object **is** emitted with
`success = $false` before the script exits:

```powershell
$result = delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
              delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj

# exit code: 5
$result.success    # $false
$result.exitCode   # 1 (or whatever MSBuild returned)
$result.output     # captured MSBuild output containing error diagnostics
```

Inspect `$result.output` to see the MSBuild error lines.  When
`-ShowOutput` is used, the output has already streamed to console and
`$result.output` is `$null`; a `Write-Error` message is emitted to
stderr instead.

------------------------------------------------------------------------

# Notes on "rsvars.bat" and Environment Variables

`rsvars.bat` typically sets the following environment variables in the Delphi
installation's own `cmd.exe` session:

  - `BDS` -- Delphi installation root
  - `BDSBIN` -- Delphi bin directory
  - `BDSCOMMONDIR` -- shared Delphi data directory
  - `FrameworkDir` -- .NET Framework directory
  - `FrameworkVersion` -- .NET Framework version string
  - `PATH` -- prepended with MSBuild and Delphi bin paths

PowerShell cannot inherit these from a `cmd.exe` side-effect directly.
`delphi-msbuild.ps1` works around this by sourcing `rsvars.bat` via:

```bash
cmd.exe /c "call rsvars.bat > nul 2>&1 && set"
```

Then each `KEY=VALUE` line from `set` is applied to the current PowerShell
process environment via `[Environment]::SetEnvironmentVariable`.  This
makes `msbuild.exe` available on `PATH` for the remainder of the session.

