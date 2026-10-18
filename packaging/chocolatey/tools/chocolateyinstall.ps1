$ErrorActionPreference = 'Stop'

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  url64bit       = 'https://github.com/FredrikBorgstrom/moviecat/releases/download/v{{VERSION}}/MovieCat-windows-x64-setup.exe'
  checksum64     = '{{CHECKSUM}}'
  checksumType64 = 'sha256'
  silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS'
  validExitCodes = @(0)
  softwareName   = 'MovieCat*'
}

Install-ChocolateyPackage @packageArgs
