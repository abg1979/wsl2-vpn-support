########### Configuration Parameters

$vpn_interface_desc = "PANGP"
$wsl_interface_name = "vEthernet (WSL (Hyper-V firewall))"

$state_file = "$HOME\wsl-added-routes.txt"

########### End Configuration Parameters

########### Start Transcript 
Start-Transcript -Path .\wsl-config.log -Append -NoClobber -IncludeInvocationHeader

Write-Output "===================="
Write-Output "= WSL2 VPN Support ="
Write-Output "===================="

# Get list of IPs for the WSL Guest(s)
Write-Output "Determining IP Addresses of WSL2 Guest(s) ..."
# Using the HNS module from here https://www.powershellgallery.com/packages/HNS/0.2.4
# It helps in getting the android subsystem have network as well.
$wsl_guest_ips = (Get-HnsEndpoint | Select-Object -ExpandProperty IPAddress)
Write-Output "WSL2 Guest IP Addresses: Current  = $wsl_guest_ips"

# Load Previous rules from file
Write-Output "Checking for previous configuration ..."
$previous_ips = [System.Collections.ArrayList]@()
if ((Test-Path $state_file)) {
    Write-Output "Loading State"
    foreach ($item IN (Get-Content -Path $state_file)) {
        $previous_ip = $item.Trim()
        $previous_ips.Add($previous_ip)
    }
}
Write-Output "WSL2 Guest IP Addresses: Previous (Stored) = $previous_ips"
if ($null -ne $wsl_guest_ips) {
    $index = 0
    for (; $index -le ($previous_ips.Count - 1);) {
        $previous_ip = $previous_ips[$index]
        if ($wsl_guest_ips.Contains($previous_ip)) {
            Write-Output "$previous_ip is still running."
            $previous_ips.Remove($previous_ip)
            continue
        }
        $index += 1
    }
}
Write-Output "WSL2 Guest IP Addresses: Previous (Revised) = $previous_ips"

# Check if VPN Gateway is UP
Write-Output "Checking VPN State ..."
$vpn_state = (Get-NetAdapter -IncludeHidden | Where-Object {$_.InterfaceDescription -Match "$vpn_interface_desc"} | Select-Object -ExpandProperty Status)
Write-Output "VPN Connection Status: $vpn_state"

if ($vpn_state -eq "Up") {
    Write-Output "VPN is UP"

    # Get key metrics for the WSL Network Interface
    Write-Output "Determining WSL2 Interface parameters ..."
    $wsl_interface_index = (Get-NetAdapter -Name "$wsl_interface_name" -IncludeHidden -ErrorAction Ignore | Select-Object -ExpandProperty ifIndex)
    if ($wsl_interface_index) {
        Write-Output "WSL2 Interface Parameters: Index = $wsl_interface_index"
        Write-Output "Determining VPN Interface parameters ..."
        $vpn_interface_index = (Get-NetAdapter -IncludeHidden | Where-Object {$_.InterfaceDescription -Match "$vpn_interface_desc"} | Select-Object -ExpandProperty ifIndex)
        $vpn_interface_routemetric = (Get-NetRoute -InterfaceIndex $vpn_interface_index | Select-Object -ExpandProperty RouteMetric | Sort-Object -Unique | Select-Object -First 1)
        Write-Output "VPN Interface Parameters: Index = $vpn_interface_index"
        Write-Output "VPN Interface Parameters: RouteMetric (Actual) = $vpn_interface_routemetric"
        if ($vpn_interface_routemetric -eq 0) { $vpn_interface_routemetric = 1 }
        Write-Output "VPN Interface Parameters: RouteMetric (Adjusted) = $vpn_interface_routemetric"

        # Create rules for each WSL guest
        Write-Output "Creating routes ..."
        Write-Output $wsl_guest_ips | Out-File -FilePath $state_file
        foreach ($ip IN $wsl_guest_ips) {
            Write-Output "Creating route for $ip"
            Write-Output "Command: route add $ip mask 255.255.255.255 $ip metric $vpn_interface_routemetric if $wsl_interface_index"
            # route add $ip mask 255.255.255.255 $ip metric $vpn_interface_routemetric if $wsl_interface_index
            # check existing routes
            $existing_routes = (Get-NetRoute -DestinationPrefix $ip/32 -NextHop $ip)
            if ($existing_routes) {
                Write-Output "Route already exists."
            } else {
                Write-Output "Route does not exist. Creating it ..."
                New-NetRoute -DestinationPrefix $ip/32  -NextHop $ip -RouteMetric $vpn_interface_routemetric -InterfaceIndex $wsl_interface_index
            }
        }
    } else {
        Write-Output "WSL2 is not running."
    }
} else {
    Write-Output "VPN is DOWN"
    Write-Output "" | Out-File -FilePath $state_file
}

# Clean up previous IPs
Write-Output "Performing cleanup ..."
foreach ($ip IN $previous_ips) {
    if ($ip.Trim() -ne "") {
        Write-Output "Deleting route for $ip"
        Write-Output "Command: route delete $ip mask 255.255.255.255 $ip"
        # check existing routes
        $existing_routes = (Get-NetRoute -DestinationPrefix $ip/32 -NextHop $ip)
        if ($existing_routes) {
            Write-Output "Route already exists. Deleting it ..."
            # route delete $ip mask 255.255.255.255 $ip
            Remove-NetRoute -DestinationPrefix $ip/32 -NextHop $ip -Confirm:$false
        } else {
            Write-Output "Route does not exist."
        }
    }
}

Write-Output "Done"

Stop-Transcript