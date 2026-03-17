# delphi-msbuild

![delphi-msbuild logo](https://continuous-delphi.github.io/assets/logos/delphi-msbuild-480x270.png)

[![CI](https://github.com/continuous-delphi/delphi-msbuild/actions/workflows/ci.yml/badge.svg)](https://github.com/continuous-delphi/delphi-msbuild/actions/workflows/ci.yml)
![Status](https://img.shields.io/badge/status-incubator-orange)
![License](https://img.shields.io/github/license/continuous-delphi/delphi-inspect.svg)
![Delphi](https://img.shields.io/badge/delphi-red)
![PowerShell](https://img.shields.io/badge/powershell-blue)
![Continuous Delphi](https://img.shields.io/badge/org-continuous--delphi-red)

Quick-start, or enhance your Delphi build automation with a standalone,
MIT-licensed, CI-ready build tool from
[Continuous-Delphi](https://github.com/continuous-delphi) -
designed for automating builds using MSBuild.
See [delphi-dccbuild](https://github.com/continuous-delphi/delphi-dccbuild)
for a similar tool that utilizes the DCC command line compilers.

# Overview

`delphi-msbuild.ps1` builds a Delphi `.dproj` project using
MSBuild.  It sources the Delphi build environment from `rsvars.bat`
(located under the Delphi installation root) and then invokes MSBuild
with the requested project file, platform, and configuration.

It is designed to be used standalone by providing the `ProjectFile` path
and the Delphi `RootDir` (and optionally the Platform and Config settings.)

```powershell
delphi-msbuild.ps1 `
  -ProjectFile .\src\MyApp.dpr `
  -RootDir     'C:\Program Files (x86)\Embarcadero\Studio\23.0' 
```

You can also pipe the output from `delphi-inspect.ps1` to automatically
detect the `RootDir`:

```powershell
delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
      delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj
```

## PowerShell Compatibility

Runs on the widely available Windows PowerShell 5.1 (`powershell.exe`)
and the newer PowerShell 7+ (`pwsh`).

Note: the test suite requires `pwsh`.

# Usage

```powershell
pwsh delphi-msbuild.ps1 -ProjectFile <path> [options]
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

## -ExeOutputDir

```text
-ExeOutputDir <path>
```

Output directory for the compiled executable or library.  Passed to MSBuild as
`/p:DCC_ExeOutput=<path>`.

When omitted, MSBuild uses the output location defined in the project's
PropertyGroups.  The result object's `.exeOutputDir` is `$null` when this
parameter is not supplied.

## -DcuOutputDir

```text
-DcuOutputDir <path>
```

Output directory for compiled `.dcu` files.  Passed to MSBuild as
`/p:DCC_DcuOutput=<path>`.

When omitted, MSBuild uses the DCU location from the project's PropertyGroups.
The result object's `.dcuOutputDir` is `$null` when this parameter is not
supplied.

## -UnitSearchPath

```text
-UnitSearchPath <path[]>
```

Additional unit search paths appended to the project's existing unit path.
Accepts an array of path strings.  Multiple paths are joined with semicolons
and passed as:

```text
/p:DCC_UnitSearchPath="$(DCC_UnitSearchPath);path1;path2"
```

The `$(DCC_UnitSearchPath)` prefix preserves the paths already set in the
project's PropertyGroups.  Without it, the assignment would replace them
entirely.

When omitted (or an empty array), no `/p:DCC_UnitSearchPath` argument is added.
The result object's `.unitSearchPath` is `$null` when no paths are supplied.

Example:

```powershell
-UnitSearchPath @('C:\Libs\A', 'C:\Libs\B')
```

## -Define

```text
-Define <string[]>
```

One or more additional MSBuild defines to pass to the compiler.  When at least
one value is supplied, the script appends the following to the MSBuild command
line:

```text
/p:DCC_Define="$(DCC_Define);DEFINE1;DEFINE2"
```

The `$(DCC_Define)` prefix preserves the defines already set by the project's
PropertyGroups (e.g. `DEBUG`, `RELEASE`).  Without it, the property assignment
would replace them entirely.

When no `-Define` values are supplied (the default), the `/p:DCC_Define`
argument is omitted entirely.

Examples:

```powershell
# Single define
delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj -RootDir $root -Define CI

# Multiple defines
delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj -RootDir $root `
    -Define MYFLAG, USE_JEDI_JCL

# Via pipeline with defines
delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem MSBuild |
    delphi-msbuild.ps1 -ProjectFile .\src\MyApp.dproj -Define CI, MYFLAG
```

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

| Property         | Type     | Description                                              |
|------------------|----------|----------------------------------------------------------|
| `projectFile`    | string   | Absolute path to the project file                        |
| `platform`       | string   | Platform value used (e.g. `Win32`)                       |
| `config`         | string   | Config value used (e.g. `Debug`)                         |
| `target`         | string   | Target used (e.g. `Build`)                               |
| `rootDir`        | string   | Resolved Delphi installation root                        |
| `rsvarsPath`     | string   | Derived path to `rsvars.bat`                             |
| `exeOutputDir`   | string   | Value of `-ExeOutputDir`; `$null` when not supplied      |
| `dcuOutputDir`   | string   | Value of `-DcuOutputDir`; `$null` when not supplied      |
| `unitSearchPath` | string[] | Value of `-UnitSearchPath`; `$null` when not supplied    |
| `exitCode`       | int      | MSBuild process exit code                                |
| `success`        | bool     | `$true` when `exitCode` is 0                             |
| `output`         | string   | Captured MSBuild output; `$null` when `-ShowOutput`      |

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


# Comparison with delphi-dccbuild.ps1

| Aspect               | delphi-dccbuild.ps1          | delphi-msbuild.ps1              |
|----------------------|------------------------------|---------------------------------|
| Project file type    | `.dpr`                       | `.dproj`                        |
| Build system         | `dcc*.exe`                   | `msbuild.exe`                   |
| Environment setup    | Sources `rsvars.bat`         | Sources `rsvars.bat`            |
| Config parameter     | Added as define (`-DDEBUG`)  | Passed as `/p:Config=Debug`     |
| Target: Rebuild      | `-B` flag                    | `/t:Rebuild`                    |
| Target: Clean        | Not available                | `/t:Clean`                      |
| Verbosity options    | `quiet`, `normal`            | `quiet` through `diagnostic`    |
| Result `rsvarsPath`  | Present                      | Present                         |
| Result `compilerPath`| Present                      | Not present                     |
| Inspect -BuildSystem | `DCC`                        | `MSBuild`                       |

Both scripts use the same `-RootDir` parameter and accept the same
pipeline object shape (`.rootDir` property), so the same
`delphi-inspect.ps1 -DetectLatest` result object works with either.


## Maturity

This repository is currently `incubator`. Both implementations are under active development.
It will graduate to `stable` once:

- At least one downstream consumer exists.

Until graduation, breaking changes may occur

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

## Part of the Continuous Delphi Organization

This repository follows the Continuous Delphi organization taxonomy. See
[cd-meta-org](https://github.com/continuous-delphi/cd-meta-org) for navigation and governance.

- `docs/org-taxonomy.md` -- naming and tagging conventions
- `docs/versioning-policy.md` -- release and versioning rules
- `docs/repo-lifecycle.md` -- lifecycle states and graduation criteria
