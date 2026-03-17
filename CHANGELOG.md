# Changelog

All notable changes to this project will be documented in this file.

---
## [0.3.0] - Unreleased

- Add `-ExeOutputDir` parameter to set the compiled executable output directory
  via `/p:DCC_ExeOutput`
- Add `-DcuOutputDir` parameter to set the compiled DCU output directory
  via `/p:DCC_DcuOutput`
- Add `-UnitSearchPath` parameter to append additional unit search paths
  via `/p:DCC_UnitSearchPath=$(DCC_UnitSearchPath);...`, preserving paths
  already set by the project's PropertyGroups
[#11](https://github.com/continuous-delphi/delphi-msbuild/issues/11)

- Add support for passing compiler defines to MSBUILD
  [#9](https://github.com/continuous-delphi/delphi-msbuild/issues/9)

## [0.2.0] - 2026-03-16

- Added `delphi-msbuild.ps1` to be a direct download on the release page
  [#5](https://github.com/continuous-delphi/delphi-msbuild/issues/5)

## [0.1.0] - 2026-03-16

- Initial release of `delphi-msbuild.ps1` -- build Delphi `.dproj` projects
  via MSBuild from the command line, with support for piped output from
  `delphi-inspect` and automatic `rsvars.bat` environment sourcing.
  [#1](https://github.com/continuous-delphi/delphi-msbuild/issues/1)


<br />
<br />

## `delphi-msbuild` - a developer tool from Continuous Delphi

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

https://github.com/continuous-delphi
