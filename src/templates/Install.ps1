param($installPath, $toolsPath, $package, $project)

Write-Host "Install script running..."
# Write-Host "`tInstallPath: $installPath"
# Write-Host "`tToolsPath: $toolsPath"
Write-Host "`tPackage: $($package.Id)"
# Write-Host "`tProject: $($project.Name)"

[System.IO.Directory]::SetCurrentDirectory($project.Properties.Item("FullPath").Value)
Write-Host "`tCurrent directory: $([System.IO.Directory]::GetCurrentDirectory())"


# if there isn't a project file, there is nothing to do
if (!$project) 
{ 
	Write-Host "Parameters do not include project reference.  Exiting."

	return; 
}

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.Packaging") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.Configuration.IO") | Out-Null

function AddManagementPackReference([Microsoft.EnterpriseManagement.Configuration.ManagementPack] $managementPack, [string] $hintPath)
{
	$identity = "$($managementPack.Name) (Version=$($managementPack.Version), PublicKeyToken=$($managementPack.KeyToken))"

    #make hint path relative
    $hintPath = "..$($hintPath.Substring($hintPath.IndexOf("\packages")))"

	if ($managementPack.Sealed)
	{
		$packReferenceNode = $null
		try
		{
			[string]$mpName = $managementPack.Name
			$packReferenceNode = New-Object Microsoft.SystemCenter.Authoring.ProjectSystem.ManagementPackReferenceNode -Args @($projectMgr, $hintPath, $mpName)

			[Microsoft.VisualStudio.Project.ReferenceNode] $existingEquivalentNode = $null

			$isAlreadyAdded = $isAlreadyAddedMethodInfo.Invoke($packReferenceNode, @($existingEquivalentNode))

			if (-not $isAlreadyAdded)
			{
				$packReferenceNode.AddReference()
                Write-Host "`tReference to $($packReferenceNode.Name) added."

                $preferredAlias = ((import-csv "$toolsPath\PreferredAlias.csv") | where {$_.Name -eq $packReferenceNode.Name} | select -first 1).Alias
        
                if (-not [string]::IsNullOrEmpty($preferredAlias))
                {
					Write-Host "`tSetting preferred alias ($preferredAlias) on $($packReferenceNode.Name)."
                    $setAliasMethodInfo.Invoke($packReferenceNode, @($preferredAlias))
                }
			}
            else { Write-Host "`tReference to $($packReferenceNode.Name) already exists."}

		}
		finally
		{
			if ($packReferenceNode -is [IDisposable]) { $packReferenceNode.Dispose() }
		}
	}
}

function AddManagementPackReferencesFromBundle([string] $path)
{
	$bundleReader = [Microsoft.EnterpriseManagement.Packaging.ManagementPackBundleFactory]::CreateBundleReader()
 
	$mpFileStore = $null
	try
	{
		$mpFileStore = New-Object Microsoft.EnterpriseManagement.Configuration.IO.ManagementPackFileStore
		
		$bundle = $bundleReader.Read($path, $mpFileStore)
		
		foreach ($pack in $bundle.ManagementPacks) 
		{
			try
			{
				AddManagementPackReference $pack $path
			}
			finally
			{
				if ($managementPack -is [IDisposable]) { $managementPack.Dispose() }
			}
		}
		
	}
	finally
	{
		if ($mpFileStore -is [IDisposable]) { $mpFileStore.Dispose() }
	}
}

function AddManagementPackReferenceFromSealedMp([string] $path)
{
	[Microsoft.EnterpriseManagement.Configuration.IO.ManagementPackFileStore] $mpFileStore = $null
	try
	{
		$mpFileStore = New-Object Microsoft.EnterpriseManagement.Configuration.IO.ManagementPackFileStore
        
		$mpFileStore.AddDirectory([System.IO.Path]::GetDirectoryName($path))

		[Microsoft.EnterpriseManagement.Configuration.ManagementPack] $managementPack = $null
		try
		{
			$pack = New-Object Microsoft.EnterpriseManagement.Configuration.ManagementPack $path, $mpFileStore

			AddManagementPackReference $pack $path
		}
		finally
		{
			if ($managementPack -is [IDisposable]) { $managementPack.Dispose() }
		}
	}
	finally
	{
		if ($mpFileStore -is [IDisposable]) { $mpFileStore.Dispose() }
	}
}


[Microsoft.SystemCenter.Authoring.ProjectSystem.ManagementPackProjectNode]$projectMgr = $project.Object
$oaReferenceFolderItem = $project.ProjectItems.Item(1)
$bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic 
$refFolderType = $oaReferenceFolderItem.GetType()
$refFolderPropinfo = $refFolderType.GetProperty("Node", $bindingFlags)
$bindingFlags = $bindingFlags -bor [System.Reflection.BindingFlags]::DeclaredOnly

[Microsoft.SystemCenter.Authoring.ProjectSystem.ManagementPackReferenceContainerNode]$mpReferenceContainerNode = $refFolderPropinfo.GetValue($oaReferenceFolderItem)
$isAlreadyAddedMethodInfo = [Microsoft.SystemCenter.Authoring.ProjectSystem.ManagementPackReferenceNode].GetMethod("IsAlreadyAdded", $bindingFlags)
$setAliasMethodInfo = [Microsoft.SystemCenter.Authoring.ProjectSystem.ManagementPackReferenceNode].GetMethod("SetAlias", $bindingFlags)

$candidateReferences = gci "$installPath\lib\SCMPInfra"

foreach ($candidateReference in $candidateReferences)
{
	$referencePath = $candidateReference.FullName
	$extension = [System.IO.Path]::GetExtension($referencePath)
	switch ($extension)
	{
		".mpb" 
		{
	        Write-Host "`tEnsuring reference to bundle: $($candidateReference.Name)"
		    AddManagementPackReferencesFromBundle $referencePath
		}
		".mp"
		{
	        Write-Host "`tEnsuring reference to pack: $($candidateReference.Name)"
			AddManagementPackReferenceFromSealedMp $referencePath
		}
	}
}

# Run custom install
& "$toolsPath\CustomInstall.ps1" -installPath $installPath -toolsPath $toolsPath -package $package -project $project

