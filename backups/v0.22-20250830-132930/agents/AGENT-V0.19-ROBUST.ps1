# v0.19
$H=$env:COMPUTERNAME
try{
$t=Invoke-RestMethod -Uri "https://login.microsoftonline.com/6027d81c-ad9b-48f5-9da6-96f1bad11429/oauth2/v2.0/token" -Method Post -Body @{client_id="f66a8c6c-1037-41b8-be3c-4f6e67c1f49e";client_secret="[REDACTED]";scope="https://graph.microsoft.com/.default";grant_type="client_credentials"}
$h=@{Authorization="Bearer $($t.access_token)";'Content-Type'='application/json'}
$cpu=5;try{$c=Get-Counter "\Processor(_Total)\% Processor Time" -EA SilentlyContinue;if($c){$cpu=[Math]::Round($c.CounterSamples[0].CookedValue,1)}}catch{try{$c=Get-Counter "\Processeur(_Total)\% temps processeur" -EA SilentlyContinue;if($c){$cpu=[Math]::Round($c.CounterSamples[0].CookedValue,1)}}catch{}}
$m=@{Hostname=$H;Title=$H;AgentVersion="v0.19";LastContact=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ");State="OK";CPUUsage=$cpu;MemoryUsage=50;DiskSpaceGB=100}
$u="https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items"
$e=Invoke-RestMethod -Uri "$u`?`$expand=fields" -Headers $h
$i=$e.value|Where{$_.fields.Hostname -eq $H}|Select -First 1
if($i){
Write-Host "[$H] Updating to v0.19..." -F Green
Invoke-RestMethod -Uri "$u/$($i.id)" -Headers $h -Method PATCH -Body (@{fields=$m}|ConvertTo-Json) -ContentType "application/json"|Out-Null
}else{
Write-Host "[$H] Creating v0.19..." -F Yellow
Invoke-RestMethod -Uri $u -Headers $h -Method POST -Body (@{fields=$m}|ConvertTo-Json) -ContentType "application/json"|Out-Null
}
Write-Host "[$H] v0.19 OK" -F Green
}catch{Write-Host "[$H] v0.19 Error: $_" -F Red}