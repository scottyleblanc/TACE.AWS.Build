#Requires -Version 7.0

function Assert-AwsCliAvailable {
    <#
    .SYNOPSIS
        Validates that the AWS CLI v2 is available.

    .DESCRIPTION
        Checks for the presence of the AWS CLI (v2) and confirms the version.
        Throws a descriptive error if the CLI is missing or below v2. Called by
        public functions before making any AWS API calls.

    .NOTES
        Private function — not exported from the module.
    #>
    [CmdletBinding()]
    param ()

    try {
        $null = Get-Command aws -ErrorAction Stop
    }
    catch {
        throw "AWS CLI not found. Install from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    }

    try {
        $cliVersion = aws --version 2>&1
        if ($cliVersion -notmatch 'aws-cli/2\.') {
            throw "AWS CLI v2 is required. Current version: $cliVersion"
        }
    }
    catch {
        throw "Unable to determine AWS CLI version: $($_.Exception.Message)"
    }
}
