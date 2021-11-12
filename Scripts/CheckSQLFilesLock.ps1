function Test-FileLock {
  param (
    [parameter(Mandatory=$true)][string]$Path
  )

  $oFile = New-Object System.IO.FileInfo $Path

  if ((Test-Path -Path $Path) -eq $false) {
    return $false
  }

  try {
    $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

    if ($oStream) {
      $oStream.Close()
    }
    return $false
  } catch {
    # file is locked by a process.
    return $true
  }
}

$volumes = Get-Volume | Where-Object {($_.DriveType -in "Fixed") -and ($_.FileSystemLabel -ne "System Reserved")}
foreach ($v in $volumes){
    #if ($v.DriveLetter -in "C", " ", "" ){
    if ($v.DriveLetter -in "", " ", "" ){
        continue;
    }
    elseif ($v.DriveLetter -in "C"){
        $path = "C:\Program Files\Microsoft SQL Server\";
    }
    else{
        $path = "$($v.DriveLetter):\";
    }

    $files = Get-ChildItem -Path "$($path)" -Recurse | Where-Object {$_.extension -in ".mdf",".ldf",".ndf"}
    foreach ($f in $files){
        if ($(Test-FileLock $f.FullName) -eq $true){
            Write-Output "Locked -> $($f.FullName)"
            continue;
        }
        else{
            Write-Output "Not Locked -> $($f.FullName)"
        }
    }
}