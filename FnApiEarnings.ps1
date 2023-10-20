# Perform the GET request to retrieve the account ID
$token = "YOUR-TOKEN-GOES-HERE"  # Replace with your Fortnite API authorization token
$lookupUrl = "https://fortniteapi.io/v1/events/window?windowId=$windowId"
# Initialize an array to hold all event objects
$allEvents = @()

$lookupUrl = "https://fortniteapi.io/v1/events/list?lang=en"

$headers = @{
    "Authorization" = "$token"
}

try {
    $response = Invoke-RestMethod -Uri $lookupUrl -Headers $headers -Method Get -ErrorAction Stop

    # Check if the response contains the 'events' property
    if ($response.events -ne $null) {
        $events = $response.events

        # Create an empty array to store windowIds
        $windowIds = @()

        # Iterate through each event
        foreach ($event in $events) {
            $windows = $event.windows

            # Iterate through each window in the event
            foreach ($window in $windows) {
                $windowId = $window.windowId
                
                # Add the windowId to the array
                $windowIds += $windowId
            }
        }

        # Join the windowIds into a comma-separated string
        $windowIdsString = $windowIds -join ','
    }
}
catch {
    Write-Host "An error occurred retrieving windowIds: $_"
}

# Check if the output.json file exists
if (Test-Path -Path "output.json") {
    try {
        $existingData = Get-Content -Path "output.json" -Raw | ConvertFrom-Json

        # Check if the windowId exists in the JSON data
        $existingIds = $existingData | ForEach-Object { $_.eventId }
    }
    catch {
        Write-Host "Error reading or parsing the existing JSON data: $_"
    }
}
$existingIdCounter = 0
$errorCounter = 0

# Iterate through the windowIds
foreach ($windowId in $windowIdsString.Split(",")) {
    # Check if the windowId exists in the existing data
    if ($existingIds -contains $windowId) {
        Write-Host "$existingIdCounter"
		$existingIdCounter++
        continue
    }
    else 
    {
        # If the windowId doesn't exist in output.json or the file doesn't exist, perform the API request
        $lookupUrl = "https://fortniteapi.io/v1/events/window?windowId=$windowId"

        Write-Host "$lookupUrl"

        try {
            $response = Invoke-RestMethod -Uri $lookupUrl -Headers $headers -Method Get -ErrorAction Stop

            # Check if the response contains the 'session' property
            if ($response.session -ne $null) {
                $windowId = $response.session.windowId

                # Create an object to store the event data
                $event = @{
                    eventId = $windowId
                    earnings = @()
                }

                # Check if the response contains the 'payout' property under 'session'
                if ($response.session.payout -ne $null) {
                    Write-Host "Processed"

                    # Create an array to store earnings data
                    $earnings = @()

                    # Create an array to store payout thresholds and quantities
                    $payouts = $response.session.payout.ranks | ForEach-Object {
                        [PSCustomObject]@{
                            Threshold = $_.threshold
                            Quantity = $_.payouts[0].quantity
                        }
                    }

                    # Define the minimum and maximum ranks you want to display
                    $minRank = 1
                    $maxRank = 100

                    # Loop through ranks from the minimum rank to the maximum rank
                    for ($rank = $minRank; $rank -le $maxRank; $rank++) {
                        # Find the closest lower rank's payout
                        $closestPayout = $payouts | Where-Object { $_.Threshold -le $rank } | Sort-Object Threshold -Descending | Select-Object -First 1

                        # Display the closest lower rank's quantity
                        if ($closestPayout -ne $null) {
                            $quantity = $closestPayout.Quantity
                        }
                        else {
                            # If there's no matching rank, set quantity to "unknown"
                            $quantity = "unknown"
                        }

                        # Get teamAccountIds for the current rank
                        $teamAccountIds = $response.session.results[$rank - 1].teamAccountIds
                        if ([string]::IsNullOrEmpty($teamAccountIds)) {
                            # If teamAccountIds is empty, set it to "unknown"
                            $teamAccountIds = @("unknown")
                        }

                        # Create a dictionary to store earnings data
                        $earningsData = @{}
                        foreach ($accountId in $teamAccountIds) {
                            $earningsData[$accountId] = "$quantity USD"
                        }

                        # Add earnings data to the array
                        $earnings += $earningsData
                    }

                    # Add the earnings array to the event object
                    $event.earnings = $earnings
                }
                else {
                    # If the 'payout' property doesn't exist, create an empty object with the 'windowId'
                    $event = @{
                        eventId = $windowId
                        earnings = @()
                    }
                }

                # Add the event to the array of all events
                $allEvents += $event
            }
            else {
                Write-Host "No session data found for windowId $windowId"
            }
        }
		catch {
			$errorMessage = $_.ErrorDetails.Message
			$errorJson = $errorMessage | ConvertFrom-Json -ErrorAction SilentlyContinue

			if ($errorJson -and $errorJson.error.code -eq "SERVER_ERROR") {
				Write-Host "$errorCounter"
				$errorCounter++
				Write-Host "An error occurred: $errorJson for windowId $windowId"
				# Custom handling for the 'SERVER_ERROR' case
				# You can add your logic here for this specific error case

				# Add an empty object with 'windowId' to the event array
				$event = @{
					eventId = $windowId
					earnings = @()
				}

				# Add the event to the array of all events
				$allEvents += $event
			}
		}
    }
}

# Combine the existing data and new data
if ($existingData) {
    $combinedData = $existingData + $allEvents
}
else {
    $combinedData = $allEvents
}

# Convert the combined data to JSON
$combinedDataJson = $combinedData | ConvertTo-Json -Depth 100

# Write the JSON to the output.json file
$combinedDataJson | Set-Content -Path "output.json" -Encoding UTF8
