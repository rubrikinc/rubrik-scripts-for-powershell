

Connect-Rubrik -Server 172.17.28.14 -Username peter.milanese@rubrik.demo -Password (ConvertTo-SecureString "Big13ros$" -asplaintext -force) 

Set-RubrikBlackout -Set false

