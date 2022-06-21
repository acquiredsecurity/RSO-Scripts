$dir = 'C:\ProgramData\Sentinel\RSO'
Get-ADUser -Filter * -Properties Created, Name, SID, DistinguishedName, PasswordLastSet, PasswordNeverExpires | Select-Object Created, Name, SID, DistinguishedName, PasswordLastSet, PasswordNeverExpires | Export-Csv -Path $dir/aduser.csv -NoTypeInformation
