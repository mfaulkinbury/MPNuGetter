param($installPath, $toolsPath, $package, $project)

Write-Host "Install script running..."
# Write-Host "`tInstallPath: $installPath"
# Write-Host "`tToolsPath: $toolsPath"
Write-Host "`tPackage: $($package.Id)"
# Write-Host "`tProject: $($project.Name)"

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.Packaging") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.Configuration.IO") | Out-Null

function AddManagementPackReference([Microsoft.EnterpriseManagement.Configuration.ManagementPack] $managementPack, [string] $hintPath)
{
	$identity = "$($managementPack.Name) (Version=$($managementPack.Version), PublicKeyToken=$($managementPack.KeyToken))"

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
                $preferredAlias = (get-content "$toolsPath\PreferredAlias.txt").Trim()

                if (-not [string]::IsNullOrEmpty($preferredAlias))
                {
                    $setAliasMethodInfo.Invoke($packReferenceNode, @($preferredAlias))
                }
        
				$packReferenceNode.AddReference()
                Write-Host "`tReference to $($packReferenceNode.Name) added."
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

