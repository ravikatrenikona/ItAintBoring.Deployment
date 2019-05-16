$global:TagLookups= @{}
$global:DestTagValues = @{}
$global:SourceTagValues = @{}


$HelperSource = @"

public class Helper
{
  public static void SetAttribute(Microsoft.Xrm.Sdk.Entity entity, string name, object value)
  {
     entity[name] = value;
  }
  
  public static void SetNullAttribute(Microsoft.Xrm.Sdk.Entity entity, string name, object value)
  {
     entity[name] = null;
  }
  
  public static string GetBaseTypes(System.Type type)
  {
    if(type.BaseType != null) return GetBaseTypes(type.BaseType) + ":" + type.ToString();
    else return type.ToString();
  }
  
  public static string GetObjectTypes(System.Object obj)
  {
    return GetBaseTypes(obj.GetType());
  }
}
"@


function Get-Types($param)
{
  return [Helper]::GetObjectTypes($param)
}

#A workaround for PSObject wrapping/unwrapping
#Seems to work, so all good
function Set-Attribute($entity, $name, $value)
{
   if($value -eq $null){ [Helper]::SetNullAttribute($entity, $name, $value) }
   else{  [Helper]::SetAttribute($entity, $name, $value) }
}

function Custom-GetConnection($conString)
{
  return [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]::New($conString);
}

function Get-EntityFilters()
{
	return [Microsoft.Xrm.Sdk.Metadata.EntityFilters]::Attributes
}

function Get-AttributeTypeName($typeCode)
{
   switch ($typeCode.Value)
     {
         ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::LookupType).Value { return "entityReference" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::MoneyType).Value { return "money" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::DecimalType).Value { return "decimal" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::StringType).Value { return "string" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::PicklistType).Value { return "optionSet" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::BooleanType).Value { return "bool" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::VirtualType).Value { return "virtual" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::DoubleType).Value { return "double" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::IntegerType).Value { return "integer" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::DateTimeType).Value { return "dateTime" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::UniqueidentifierType).Value { return "guid" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::StatusType).Value { return "status" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::StateType).Value { return "state" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::CustomerType).Value { return "customer" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::BigIntType).Value { return "bigint" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::MemoType).Value { return "string" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::EntityNameType).Value { return "entityName" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::ImageType).Value { return "image" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::OwnerType).Value { return "owner" }
		 ([Microsoft.Xrm.Sdk.Metadata.AttributeTypeDisplayName]::MultiSelectPicklistType).Value { return "multiSelectOptionSet" }
		 
         default { return $typeCode }
     }
}


class CDSDeployment {
	
	[PSObject] $SourceConn = $null
	[PSObject] $DestConn = $null
	[string]   $SolutionsFolder = ""    

	[bool] CheckRecordExists([PSObject] $conn, [PSObject] $entity, $isIntersect)
	{
	    
			Try
			{
				$ColumnSet = New-Object Microsoft.Xrm.Sdk.Query.ColumnSet $true
				$conn.Retrieve($entity.LogicalName, $entity.id, $ColumnSet)
				return $true
			}
			Catch
			{
				return $false
			}
		
	}
	
	[void] UpsertRecord([PSObject] $conn, [PSObject] $entity, [PSObject] $schema)
	{
		#assuming there is always an id - this is for configuration data after all
		if($schema.isIntersect){
		    if($entity.LogicalName -eq "teamroles")
			{
			    $request = New-Object Microsoft.Xrm.Sdk.Messages.AssociateRequest
			    $request.Target = New-Object Microsoft.Xrm.Sdk.EntityReference -ArgumentList @("role", $entity["roleid"])
				$request.RelatedEntities = New-Object Microsoft.Xrm.Sdk.EntityReferenceCollection
				
				$teamRef = New-Object Microsoft.Xrm.Sdk.EntityReference -ArgumentList @("team", $entity["teamid"])
				$request.RelatedEntities.Add($teamRef)
				$request.Relationship = New-Object Microsoft.Xrm.Sdk.Relationship -ArgumentList @("teamroles_association")
				try
				{
				  $conn.Execute($request)
				}
				catch
				{
				  if($_.Exception.Message.contains("Cannot insert duplicate key") -eq $false) {
				    throw
				  }
				}
    		}
		}
		else{
			$recordExists = $this.CheckRecordExists($conn, $entity, $schema.isIntersect)
			if($recordExists) { $conn.Update($entity) }
			else { $conn.Create($entity) }
		}
	}

	[void] PublishAll()
	{
	   $request = New-Object Microsoft.Crm.Sdk.Messages.PublishAllXmlRequest
	   $this.DestConn.Execute($request)
	}

	[void] ImportSolution([string] $solutionName)
	{
		$impId = New-Object Guid
		write-host "Importing solution"
		$this.DestConn.ImportSolutionToCrm("$($this.SolutionsFolder)\$solutionName.zip",[ref] $impId)
		write-host "Publishing customizations"
		$this.PublishAll()
	}

	[void] ExportSolution([string] $solutionName, [switch] $Managed = $false)
	{
		$request = New-Object Microsoft.Crm.Sdk.Messages.ExportSolutionRequest
		$request.Managed = $Managed
		$request.SolutionName = $solutionName
		$response = $this.SourceConn.Execute($request)
		if(!$Managed)
		{
		  [io.file]::WriteAllBytes("$($this.SolutionsFolder)\$solutionName.zip",$response.ExportSolutionFile)
		}
		else{
		  [io.file]::WriteAllBytes("$($this.SolutionsFolder)\${solutionName}_managed.zip",$response.ExportSolutionFile)
		}
	}
	
	

	[void] SetField([string] $entityName, [PSObject] $schema, [PSObject] $entity, [string] $fieldName, [PSObject] $value)
	{
		
		try{
			$assigned = $false
			if($value -eq $null){
			   Set-Attribute $entity $fieldName $null
			   return
			}
			
			if($schema.attributes.$fieldName -eq $null)
			{
			   write-host "$entityName.$fieldName attribute is not defined in the schema"
			   return
			}
			
			$value = $value.Trim()
			$convValue = $value

			switch($schema.attributes.$fieldName){
			   "optionSet" { $convValue = New-Object Microsoft.Xrm.Sdk.OptionSetValue $value }
			   "multiSelectOptionSet" { 
				   $stringValues = $value.Split(" ")
					[object] $valueList = foreach($number in $stringValues) {
						try {
							New-Object Microsoft.Xrm.Sdk.OptionSetValue $number
						}
						catch {
							write-host "Cannot create an option set value for $entityName.$fieldName - $value"
						}
					}
					$convValue = New-Object Microsoft.Xrm.Sdk.OptionSetValueCollection 
					$convValue.AddRange($valueList)
				}
				"money" {
				   $convValue = New-Object Microsoft.Xrm.Sdk.Money $value
				}
				"bool" {
				   $convValue = [System.Boolean]::Parse($value)
				}
				"entityReference" {
					$pair = $value.Split(":")
					$convValue = New-Object -TypeName Microsoft.Xrm.Sdk.EntityReference
					$convValue.LogicalName = $pair[0]
					$convValue.Id = $pair[1]
					$convValue.Name = $null
				}
				"guid"{
				   $convValue = [System.Guid]::Parse($value)
				}
				"entityName"{
				   $convValue = $value
				}
				default {
				   $convValue = $value
				}
			}
			Set-Attribute $entity $fieldName $convValue
		}
		catch{
		    write-host "Error setting $fieldName to $value"
			write-host $_.Exception.Message
		}
	}

	[string] GetFieldValueInternal($value)
	{
	    $typeName =  $value.GetType().ToString().Trim()
		if($typeName -eq "Microsoft.Xrm.Sdk.OptionSetValue"){
		  return $value.Value
		}
		if($typeName -eq "Microsoft.Xrm.Sdk.EntityReference"){
		  return "$($value.LogicalName):$($value.Id)"
		}
		if($typeName -eq "Microsoft.Xrm.Sdk.OptionSetValueCollection"){
		  $list = @()
		  $value | ForEach-Object -Process {
		      $list += $_.Value
		  }
		  return $list
		}
		if($typeName -eq "Microsoft.Xrm.Sdk.Money"){
		  return $value.Value
		}
		if($typeName -eq "System.Guid"){
		  return $value
		}
		return $value
	}
	
	[string] GetFieldValue($val, $tagValues)
	{
		$result = $this.GetFieldValueInternal($val)
		#replace known values with tags
	    foreach($key in $tagValues.keys){
		  $result = $result.Replace($tagValues[$key], $key)
	    }
		return $result
	}

    [string] ReplaceTags($val, $tagValues)
	{
	   foreach($key in $tagValues.keys){
	      $val = $val.Replace($key, $tagValues[$key])
	   }
	   return $val;
	}
	
	[void] PushData([string] $DataFile, [string] $SchemaFile)
	{
		write-host "Importing data..."
		
		$cdsSchema = Get-Content "$SchemaFile" | Out-String | ConvertFrom-Json 
		$json = Get-Content "$DataFile" | Out-String | ConvertFrom-Json 
	  
	    $json | ForEach-Object -Process {
			$entityName = $_.entityName
			$schema = $cdsSchema.$entityName
			if($schema -eq $null){
				write-host "There is no schema for $entityName"
			}
		    else {
			     $entity = New-Object Microsoft.Xrm.Sdk.Entity -ArgumentList $entityName
				 $_.value.PSObject.Properties | ForEach-Object -Process {
				    $fieldName = $_.Name.Trim()
					$value = $this.ReplaceTags($_.Value, $global:DestTagValues)
					if($fieldName -ne "id") {
						$this.SetField($entityName, $schema, $entity, $fieldName, $value)
					}
					else{
						$entity.id = $value
					}
				 }
				 $this.UpsertRecord($this.DestConn, $entity, $schema)
			}
		}
		
	}
	
	[void] ExportData([string] $FetchXml, [string] $DataFile)
	{
		write-host "Loading data..."
		
		$fetch = $this.ReplaceTags($FetchXml, $global:SourceTagValues)
		$query  = New-Object Microsoft.Xrm.Sdk.Query.FetchExpression $fetch
		$results = $this.SourceConn.RetrieveMultiple($query)

		$records = @()
		$results.Entities | ForEach-Object -Process{
		    $r = New-Object Object
			$records += $r
			$r | Add-Member -NotePropertyName entityName -NotePropertyValue $_.LogicalName

			$value = New-Object Object
			$r | Add-Member -NotePropertyName value -NotePropertyValue $value

			$value | Add-Member -NotePropertyName id -NotePropertyValue $_.Id

		   
			$_.Attributes | ForEach-Object -Process {
			  $value | Add-Member -NotePropertyName $_.Key -NotePropertyValue $this.GetFieldValue($_.Value, $global:SourceTagValues)
			}
			
		}

		$records | ConvertTo-Json | Out-File -FilePath $DataFile
		write-host "Done!"
	}
	
	[void] ExportSchema([string[]] $entityNames, [string] $schemaFile)
	{

	   
		write-host "Exporting schema"
		$schema = New-Object Object
		if(Test-Path -Path $schemaFile){
		   $schema = Get-Content "$schemaFile" | Out-String | ConvertFrom-Json 
		}

		$entityNames | ForEach-Object -Process {
			$request = New-Object Microsoft.Xrm.Sdk.Messages.RetrieveEntityRequest
			$request.EntityFilters = Get-EntityFilters
			$request.LogicalName = $_
			$response = $this.sourceConn.Execute($request)
			$attributes = New-Object Object
			if($schema.$($request.LogicalName) -eq $null)
			{
			    $entityObject = New-Object Object
			    $schema | Add-Member -NotePropertyName $request.LogicalName -NotePropertyValue $entityObject
			}
			
			if($schema.$($request.LogicalName).attributes -eq $null)
			{
			    $schema.$($request.LogicalName) | Add-Member -NotePropertyName "attributes" -NotePropertyValue $attributes
			}
			
			if($schema.$($request.LogicalName).isIntersect -eq $null)
			{
			    $schema.$($request.LogicalName) | Add-Member -NotePropertyName "isIntersect" -NotePropertyValue $false
			}
			
			if($schema.$($request.LogicalName).primaryIdAttribute -eq $null)
			{
			    $schema.$($request.LogicalName) | Add-Member -NotePropertyName "primaryIdAttribute" -NotePropertyValue ""
			}
			
			$schema.$($request.LogicalName).isIntersect = $response.EntityMetadata.IsIntersect 
			$schema.$($request.LogicalName).attributes = $attributes
			$schema.$($request.LogicalName).primaryIdAttribute = $response.EntityMetadata.PrimaryIdAttribute

			$response.EntityMetadata.Attributes | ForEach-Object -Process {
			    $typeName = Get-AttributeTypeName $_.AttributeTypeName
			    $attributes | Add-Member -NotePropertyName $_.LogicalName -NotePropertyValue $typeName
			}
		}
		$schema | ConvertTo-Json | Out-File -FilePath $schemaFile
	}

	[void] InitializeDeployment([Switch] $forceUpdate, [string] $sourceConnectionString, [string] $destinationConnectionString)
	{
		$currentDir = Get-Location
		$this.SolutionsFolder = Get-Location
		$this.SolutionsFolder = "$($this.SolutionsFolder)\Solutions"
		
		cd .\PSModules
		
		#Get nuget
		$sourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
		$targetNugetExe = ".\nuget.exe"

		if (!(Test-Path -Path $targetNugetExe)) {
		  Invoke-WebRequest $sourceNugetExe -OutFile $targetNugetExe
		}
		Set-Alias nuget $targetNugetExe -Scope Global 

		
		#Download and install modules

		if($forceUpdate) { Remove-Item .\Microsoft.CrmSdk.XrmTooling.CrmConnector.PowerShell -Force -Recurse -ErrorAction Ignore }
		if ($forceUpdate -OR !(Test-Path -Path .\Microsoft.CrmSdk.XrmTooling.CrmConnector.PowerShell\tools))
		{
		  write-host "installing nuget"
		  ./nuget install Microsoft.CrmSdk.XrmTooling.CrmConnector.PowerShell -ExcludeVersion -O .\
		}

		#Register XRM cmdlets
		cd .\Microsoft.CrmSdk.XrmTooling.CrmConnector.PowerShell\tools
		.\RegisterXrmTooling.ps1
		
		cd "Microsoft.Xrm.Tooling.CrmConnector.PowerShell"
		
		#No need to add connector dll manuall now that entity references are working correctly
		#Add-Type -Path Microsoft.Xrm.Tooling.Connector.dll
		
		#Register Helper class		
		$assemblyDir = Get-Location
		$refs = @("$assemblyDir\Microsoft.Xrm.Sdk.dll","System.Runtime.Serialization.dll","System.ServiceModel.dll")
		Add-Type -TypeDefinition $script:HelperSource -ReferencedAssemblies $refs

		cd $currentDir
		
		
		if (!(Test-Path -Path $this.SolutionsFolder)) {
		  New-Item -ItemType "directory" -Path $this.SolutionsFolder
		}
		
		#$this.SourceConn = Custom-GetConnection $sourceConnectionString
		#$this.DestConn = Custom-GetConnection $destinationConnectionString
		$this.SourceConn = Get-CrmConnection -ConnectionString $sourceConnectionString
		$this.DestConn = Get-CrmConnection -ConnectionString $destinationConnectionString
		
		#start reading "tag" values
	
	    #Destination lookups
		foreach($key in $global:TagLookups.keys){
		  $fetch = $global:TagLookups[$key]
		  $fetch = $this.ReplaceTags($fetch, $global:TagLookups)
		  $query  = New-Object Microsoft.Xrm.Sdk.Query.FetchExpression $fetch
		  $results = $this.DestConn.RetrieveMultiple($query)
		  $results.Entities | ForEach-Object -Process{
			$DestTagValues[$key] = $_.Id
		  }  
  	    }
		
		#Source lookups
		foreach($key in $global:TagLookups.keys){
		  $fetch = $global:TagLookups[$key]
		  $fetch = $this.ReplaceTags($fetch, $global:TagLookups)
		  $query  = New-Object Microsoft.Xrm.Sdk.Query.FetchExpression $fetch
		  $results = $this.SourceConn.RetrieveMultiple($query)
		  $results.Entities | ForEach-Object -Process{
			$SourceTagValues[$key] = $_.Id
		  }  
  	    }
		
		#end reading "tag" values	
		
		
	}

	[void] LoadModule ($m) {

		# If module is imported say that and do nothing
		if (Get-Module | Where-Object {$_.Name -eq $m}) {
			write-host "Module $m is already imported."
		}
		else {

			# If module is not imported, but available on disk then import
			if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) {
				Import-Module $m -Verbose
			}
			else {

				# If module is not imported, not available on disk, but is in online gallery then install and import
				if (Find-Module -Name $m | Where-Object {$_.Name -eq $m}) {
					Install-Module -Name $m -Force -Verbose -Scope CurrentUser
					Import-Module $m -Verbose
				}
				else {

					# If module is not imported, not available and not in online gallery then abort
					write-host "Module $m not imported, not available and not in online gallery, exiting."
					EXIT 1
				}
			}
		}
	}
}