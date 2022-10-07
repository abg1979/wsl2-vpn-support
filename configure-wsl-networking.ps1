########### Configuration Parameters

$vpn_interface_desc = "PANGP"
$wsl_interface_name = "vEthernet (WSL)"

$state_file = "$HOME\wsl-added-routes.txt"

########### End Configuration Parameters

Write-Output "===================="
Write-Output "= WSL2 VPN Support ="
Write-Output "===================="

# Get list of IPs for the WSL Guest(s)
Write-Output "Determining IP Addresses of WSL2 Guest(s) ..."
$wsl_guest_ips = (Get-HnsEndpoint | select -ExpandProperty IPAddress)
Write-Output "[DEBUG] WSL2 Guest IP Addresses: Previous (Revised) = $previous_ips"
Write-Output "[DEBUG] WSL2 Guest IP Addresses: Current  = $wsl_guest_ips"

# Load Previous rules from file
Write-Output "Checking for previous configuration ..."
$previous_ips = [System.Collections.ArrayList]@()
if ((Test-Path $state_file)) {
    Write-Output "Loading State"
    foreach ($item IN (Get-Content -Path $state_file)) {
        $previous_ip = $item.Trim()
        if ($wsl_guest_ips.Contains($previous_ip)) {
            Write-Output "$previous_ip is still running."
            continue
        }
        $arrayId = $previous_ips.Add($previous_ip)
    }
}
Write-Output "[DEBUG] WSL2 Guest IP Addresses: Previous (Stored) = $previous_ips"

# Check if VPN Gateway is UP
Write-Output "Checking VPN State ..."
$vpn_state = (Get-NetAdapter -IncludeHidden | Where-Object {$_.InterfaceDescription -Match "$vpn_interface_desc"} | select -ExpandProperty Status)
Write-Output "[DEBUG] VPN Connection Status: $vpn_state"

if ($vpn_state -eq "Up") {
    Write-Output "VPN is UP"

    # Get key metrics for the WSL Network Interface
    Write-Output "Determining WSL2 Interface parameters ..."
    $wsl_interface_index = (Get-NetAdapter -Name "$wsl_interface_name" -IncludeHidden | select -ExpandProperty ifIndex)
    Write-Output "[DEBUG] WSL2 Interface Parameters: Index = $wsl_interface_index"

    Write-Output "Determining VPN Interface parameters ..."
    $vpn_interface_index = (Get-NetAdapter | Where-Object {$_.InterfaceDescription -Match "$vpn_interface_desc"} | select -ExpandProperty ifIndex)
    $vpn_interface_routemetric = (Get-NetRoute -InterfaceIndex $vpn_interface_index | select -ExpandProperty RouteMetric | Sort-Object -Unique | Select-Object -First 1)
    Write-Output "[DEBUG] VPN Interface Parameters: Index = $vpn_interface_index"
    Write-Output "[DEBUG] VPN Interface Parameters: RouteMetric (Actual) = $vpn_interface_routemetric"
    if ($vpn_interface_routemetric -eq 0) { $vpn_interface_routemetric = 1 }
    Write-Output "[DEBUG] VPN Interface Parameters: RouteMetric (Adjusted) = $vpn_interface_routemetric"

    # Create rules for each WSL guest
    Write-Output "Creating routes ..."
    Write-Output $wsl_guest_ips | Out-File -FilePath $state_file
    foreach ($ip IN $wsl_guest_ips) {
        Write-Output "Creating route for $ip"
        Write-Output "[DEBUG] Command: route add $ip mask 255.255.255.255 $ip metric $vpn_interface_routemetric if $wsl_interface_index"
        route add $ip mask 255.255.255.255 $ip metric $vpn_interface_routemetric if $wsl_interface_index
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
        Write-Output "[DEBUG] Command: route delete $ip mask 255.255.255.255 $ip"
        route delete $ip mask 255.255.255.255 $ip
    }
}

Write-Output "Done"
