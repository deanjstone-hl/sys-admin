# Baseline coverage for stack/install-windows.ps1 per the dry-run testing
# strategy resolved in deanjstone/sys-admin#15. Every mutating action in the
# script is gated through Run-Cmd or Install-FromGitHub's dry-run branch, so
# `-DryRun` should be side-effect-free and safe to execute directly in CI —
# no mocking needed, unlike the network-dependent bash scripts.

Describe "stack/install-windows.ps1 -DryRun" {
    BeforeAll {
        # Invoke-Pester is always run from the repo root (see
        # .github/workflows/ci.yml). Computed here, inside BeforeAll, because
        # variables set at file scope (outside any Describe block) run during
        # Pester's Discovery pass and are not reliably visible to It/BeforeAll
        # blocks, which run during the separate Run pass.
        $script:RepoRoot = (Get-Location).Path
        $script:ScriptPath = Join-Path $RepoRoot "stack/install-windows.ps1"
        # *>&1, not 2>&1: the script writes its progress via Write-Host,
        # which goes to the Information stream (6), not stdout. 2>&1 only
        # merges stderr; *>&1 merges every stream so Out-String actually
        # captures what Write-Host printed.
        $script:Output = & $ScriptPath -DryRun *>&1 | Out-String
    }

    It "runs to completion without throwing" {
        $Output | Should -Match "==> Done\. Next steps:"
    }

    It "reports DryRun=True in the banner" {
        $Output | Should -Match "DryRun=True"
    }

    It "hands the gitconfig, profile and claude shims to argus-config's installer" {
        # sys-admin#153: these moved to argus-config envs/windows/. This script
        # must point at its installer and no longer copy or append them itself.
        $Output | Should -Match "installed by argus-config"
        $Output | Should -Match "argus-config\\scripts\\install-windows\.ps1"
        $Output | Should -Not -Match "\[dry-run\] Copy .*gitconfig"
        $Output | Should -Not -Match "\[dry-run\] (Append|Create) .*(powershell-profile|PROFILE)"
    }
}
