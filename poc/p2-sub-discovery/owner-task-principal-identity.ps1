# Pure, owner-safe Task Scheduler identity reconciliation.
# Windows may store Principal.UserId as DOMAIN\User, local User, UPN,
# or a SID. String comparison with WindowsIdentity.Name is NOT an identity
# proof. Resolve to SecurityIdentifier and compare canonical SID values.
# This helper has NO side effects: never registers/starts/stops any task.
Set-StrictMode -Version Latest

function Test-TTVOwnerTaskPrincipal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Principal,
        [Parameter(Mandatory)]
        [string]$ExpectedSid
    )
    try {
        if ($null -eq $Principal -or
            [string]$Principal.LogonType -ine 'Interactive' -or
            [string]$Principal.RunLevel -ine 'Limited' -or
            [string]::IsNullOrWhiteSpace([string]$Principal.UserId)) {
            return $false
        }
        $verifiedExpected = [Security.Principal.SecurityIdentifier]::new($ExpectedSid)
        $principalIdentity = ([string]$Principal.UserId).Trim()
        if ($principalIdentity -match '^S-\d+(?:-\d+){2,}$') {
            $verifiedPrincipal = [Security.Principal.SecurityIdentifier]::new(
                $principalIdentity)
        } else {
            # Fail closed on an unresolvable account: never accept a mere
            # case-insensitive string match as authority for DPAPI/profile.
            $verifiedPrincipal = [Security.Principal.NTAccount]::new(
                $principalIdentity).Translate(
                [Security.Principal.SecurityIdentifier])
        }
        return [string]::Equals(
            $verifiedExpected.Value, $verifiedPrincipal.Value,
            [StringComparison]::OrdinalIgnoreCase)
    } catch {
        # Do not expose task owner, machine/user names or raw SIDs in logs.
        return $false
    }
}
