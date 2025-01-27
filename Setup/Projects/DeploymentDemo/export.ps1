loader.ps1

#Export solution
Get-CDSSolution $global:SolutionName -Managed

#Export schema
#$entityNames = @("ita_deployedentity", "businessunit")
#Get-CDSSchema $entityNames "Data\schema.txt"

#Export data

$fetch = @'
<fetch version="1.0" output-format="xml-platform" mapping="logical" distinct="false">
  <entity name="documenttemplate">
    <attribute name="documenttemplateid" />
	<attribute name="associatedentitytypecode" />
	<attribute name="documenttype" />
	<attribute name="clientdata" />
	<attribute name="name" />
	<attribute name="content" />
	<filter type="or">
	    <condition attribute="name" operator="eq" value="Deployed Entity Print Form" />
	</filter>
  </entity>
</fetch>
'@

Get-CDSData $fetch "Data\documenttemplates.txt"

$fetch = @'
<fetch version="1.0" output-format="xml-platform" mapping="logical" distinct="false">
  <entity name="ita_deployedentity">
    <attribute name="ita_deployedentityid" />
    <attribute name="ita_name" />
    <attribute name="ita_parententity" />
    <attribute name="ita_optionset" />
    <attribute name="ita_multiselect" />
    <attribute name="ita_money_base" />
    <attribute name="ita_money" />
  </entity>
</fetch>
'@

Get-CDSData $fetch "Data\deployedentity.txt"

$fetch = @'
<fetch version="1.0" output-format="xml-platform" mapping="logical" distinct="false">
  <entity name="ita_deployedentity">
    <attribute name="ita_deployedentityid" />
    <attribute name="ita_name" />
    <attribute name="ita_parententity" />
    <attribute name="ita_optionset" />
    <attribute name="ita_multiselect" />
    <attribute name="ita_money_base" />
    <attribute name="ita_money" />
    <attribute name="statecode" />
    <attribute name="statuscode" />
  </entity>
</fetch>
'@
Get-CDSData $fetch "Data\deployedentitywithstatus.txt"

$fetch = @'
<fetch version="1.0" output-format="xml-platform" mapping="logical" distinct="false">
  <entity name="businessunit">
    <all-attributes />
	<filter type="and">
      <condition attribute="name" operator="eq" value="Test" />
    </filter>
  </entity>
</fetch>
'@
Get-CDSData $fetch "Data\businessunit.txt"

write-host "Done!"

#Wait for key down
#$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

