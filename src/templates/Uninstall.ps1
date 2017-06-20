param($installPath, $toolsPath, $package, $project)

Write-Host "Uninstall script running..."
Write-Host "`tPackage: $($package.Id)"

# if there isn't a project file, there is nothing to do
if (!$project) 
{ 
	Write-Host "Parameters do not include project reference.  Exiting."

	return; 
}

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.Packaging") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.Configuration.IO") | Out-Null

function SafeRemoveManagementPackReference([string] $referenceName)
{
    $found = $false;
	$packReferenceNode = $null

	try
	{
        foreach ($reference in $mpReferenceContainerNode.EnumReferences())
        {
            if ([string]::Equals($reference.Name, $referenceName, [System.StringComparison]::OrdinalIgnoreCase))
            {
                $found = $true;
                $packReferenceNode = $reference;
                break;
            }

            if ($reference -is [IDisposable]) { $reference.Dispose() }
        }

        if ($found)
        {
            $identity = $packReferenceNode.Name
            $shouldRemoveFromStorage = $false # the nuget folder uninstall will take care of file cleanup
            $packReferenceNode.Remove($shouldRemoveFromStorage);
            Write-Host "`t`t`tReference to $($packReferenceNode.Name) removed."
        }
        else { Write-Host "`t`t`tReference to $($packReferenceNode.Name) not found."}

	}
	finally
	{
        if ($reference -is [IDisposable]) { $reference.Dispose() }
		if ($packReferenceNode -is [IDisposable]) { $packReferenceNode.Dispose() }
	}
}


function RemoveManagementPackReferencesFromBundle([string] $fullPath)
{
	$bundleReader = [Microsoft.EnterpriseManagement.Packaging.ManagementPackBundleFactory]::CreateBundleReader()
 
	$mpFileStore = $null
 	try
	{
        $mpFileStore = New-Object Microsoft.EnterpriseManagement.Configuration.IO.ManagementPackFileStore
		
		$bundle = $bundleReader.Read($fullPath, $mpFileStore)
		
		foreach ($pack in $bundle.ManagementPacks) 
		{
			try
			{
				Write-Host "`t`tRemoving reference: $($pack.Name)"
				SafeRemoveManagementPackReference $pack.Name
			}
			finally
			{
				if ($pack -is [IDisposable]) { $pack.Dispose() }
			}
		}
		
	}
	finally
	{
		if ($mpFileStore -is [IDisposable]) { $mpFileStore.Dispose() }
	}
}

function RemoveManagementPackReferenceFromSealedMp([string] $path)
{
    $referenceName = [System.IO.Path]::GetFileNameWithoutExtension($path);

    SafeRemoveManagementPackReference $referenceName
}



[Microsoft.SystemCenter.Authoring.ProjectSystem.ManagementPackProjectNode]$projectMgr = $project.Object
$oaReferenceFolderItem = $project.ProjectItems.Item(1)
$bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic 
$refFolderType = $oaReferenceFolderItem.GetType()
$refFolderPropinfo = $refFolderType.GetProperty("Node", $bindingFlags)

[Microsoft.SystemCenter.Authoring.ProjectSystem.ManagementPackReferenceContainerNode]$mpReferenceContainerNode = $refFolderPropinfo.GetValue($oaReferenceFolderItem)

$candidateReferences = gci "$installPath\lib\SCMPInfra"

foreach ($candidateReference in $candidateReferences)
{
	$referencePath = $candidateReference.FullName
	$extension = [System.IO.Path]::GetExtension($referencePath)
	switch ($extension)
	{
		".mpb" 
		{
	        Write-Host "`tRemoving reference to bundle: $($candidateReference.Name)"
		    RemoveManagementPackReferencesFromBundle $referencePath
		}
		".mp"
		{
	        Write-Host "`tRemoving reference to pack: $($candidateReference.Name)"
			RemoveManagementPackReferenceFromSealedMp $referencePath
		}
	}
}

# Run custom uninstall
& "$toolsPath\CustomUninstall.ps1" -installPath $installPath -toolsPath $toolsPath -package $package -project $project
