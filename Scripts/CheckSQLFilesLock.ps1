Function Test-IsFileLocked {
	[cmdletbinding()]
	Param (
		[parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
		[Alias('FullName','PSPath')]
		[string[]]$Path
	)
	Process {
		ForEach ($Item in $Path) {
			#Ensure this is a full path
			$Item = Convert-Path $Item
			#Verify that this is a file and not a directory
			If ([System.IO.File]::Exists($Item)) {
				Try {
					$FileStream = [System.IO.File]::Open($Item,'Open','Write')
					$FileStream.Close()
					$FileStream.Dispose()
					$IsLocked = $False
				} Catch [System.UnauthorizedAccessException] {
					$IsLocked = 'AccessDenied'
				} Catch {
					$IsLocked = $True
				}
				[pscustomobject]@{
					File = $Item
					IsLocked = $IsLocked
				}
			}
		}
	}
}



$volumes = Get-Volume | Where-Object {($_.DriveType -in "Fixed") -and ($_.FileSystemLabel -ne "System Reserved")}
foreach ($v in $volumes){
	
    #if ($v.DriveLetter -in "C", " ", "" ){
	if ($v.DriveLetter -in $null, "", " ", "" ){
		continue;
	}
	elseif ($v.DriveLetter -in "C"){
		$path = "C:\SQL\";
	}
	else{
		$path = "$($v.DriveLetter):\";
	}

    $files = Get-ChildItem -Path "$($path)" -Recurse | Where-Object {$_.extension -in ".mdf",".ldf",".ndf"}
	foreach ($f in $files){
		if ($(Test-IsFileLocked $f.FullName).IsLocked -eq $true){
			Write-Output "Locked -> $($f.FullName)"
			continue;
		}
		else{
			Write-Output "Not Locked -> $($f.FullName)"
		}
	}
}