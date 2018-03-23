$dataArray = @()

#$servers = Get-Content .\Serverlist.txt

$systems = @{
    1 = 'OU=Servers,DC=domain,DC=local'
    2 = 'OU=Computers,DC=domain,DC=local'
}

For($OUC = 1; $OUC -le $systems.Count; $OUC++) {
    $OU = $systems[$OUC]
    $machines = Get-ADComputer -SearchBase "$OU" -Filter * -Properties Name | select Name

    # MAKE FAKE ENTRY - DRIVES C E F G H Z

    # RESET dataArray

    ForEach ($computer in $machines) {

        $comp = $computer.Name
        #Run the commands concurrently for each server in the list 
        $CPUInfo = Get-WmiObject Win32_Processor -ComputerName $comp #Get CPU Information 
        $OSInfo = Get-WmiObject Win32_OperatingSystem  -ComputerName $comp #Get OS Information 

        #Get Memory Information. The data will be shown in a table as MB, rounded to the nearest second decimal. 
        $PhysicalMemory = Get-WmiObject CIM_PhysicalMemory -ComputerName $comp | Measure-Object -Property capacity -Sum | % {[math]::round(($_.sum / 1GB),2)} 

        $infoObject = New-Object PSObject 

        #The following add data to the infoObjects.
        Add-Member -inputObject $infoObject -memberType NoteProperty -name "Server Name" -value $comp
        Add-Member -inputObject $infoObject -memberType NoteProperty -name "CPU Name" -value $CPUInfo.Name
        Add-Member -inputObject $infoObject -memberType NoteProperty -name "CPU Number Of Cores" -value $CPUInfo.NumberOfCores
    
        # Report on hard drives
        $HDInfo = Get-WmiObject Win32_LogicalDisk -Filter "DriveType='3'" -ComputerName $comp
        ForEach($HDDrive in $HDInfo) {
            $HDId = $HDDrive.DeviceID.TrimEnd(":")
            $HDSize = [Math]::Round($HDDrive.Size / 1GB)
            $HDFreeSpace = [Math]::Round($HDDrive.Freespace / 1GB)
            Add-Member -inputObject $infoObject -memberType NoteProperty -name "HD $HDId Size" -value $HDSize
            Add-Member -inputObject $infoObject -memberType NoteProperty -name "HD $HDId FreeSpace" -value $HDFreeSpace
        }
    
        Add-Member -inputObject $infoObject -memberType NoteProperty -name "OS_Name" -value $OSInfo.Caption 
        Add-Member -inputObject $infoObject -memberType NoteProperty -name "OS_Version" -value $OSInfo.Version 

        Add-Member -inputObject $infoObject -memberType NoteProperty -name "Total Physical Memory (GB)" -value $PhysicalMemory 


        $dataArray += $infoObject

    }

    $dataArray | Select-Object * -ExcludeProperty RunspaceId, PSShowComputerName | ogv -Title $OU   #Export-Csv -path .\Server_Inventory_$((Get-Date).ToString('MM-dd-yyyy')).csv -NoTypeInformation 
}
