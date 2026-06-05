$server = "localhost\mssql2019"

$sqlcred = Get-Credential;
$credentialParam = @{ Credential = $sqlcred };


$files = Get-ChildItem -Recurse "C:\Work\linn_database\_maintenance\server_health_check\ExecutionLevel1"


foreach ($f in $files){
    Invoke-Sqlcmd -ServerInstance $server `
				-Database "master" `
				-DisableVariables `
				-InputFile $f.FullName `
				-QueryTimeout 0 `
				-ConnectionTimeout 0 `
				-MaxCharLength 64000 `
				-TrustServerCertificate `
				@credentialParam;

}

