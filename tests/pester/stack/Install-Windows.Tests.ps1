# Both PowerShell scripts under scaffold (stack/install-windows.ps1,
# stack/install-wezterm.ps1) — scripts/install-windows.ps1 was retired,
# Claude Code's own install scripts now live in argus-config/scripts/ —
# are mutating install/deploy scripts with no read-only equivalent to smoke-test
# against safely (unlike stack/check-versions.sh in the bats suite). Per #15,
# substantive dry-run coverage lands in #20 — this file only proves the script
# parses and exposes the expected entry point.

Describe "stack/install-windows.ps1" {
    BeforeAll {
        # Invoke-Pester is always run from the repo root (see
        # .github/workflows/ci.yml). Computed here, inside BeforeAll, because
        # variables set at file scope (outside any Describe block) run during
        # Pester's Discovery pass and are not reliably visible to It blocks,
        # which run during the separate Run pass.
        $script:RepoRoot = (Get-Location).Path
        $script:ScriptPath = Join-Path $RepoRoot "stack/install-windows.ps1"
    }

    It "exists" {
        Test-Path $ScriptPath | Should -Be $true
    }

    It "parses without syntax errors" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "exposes a -DryRun switch" {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
        $paramBlock = $ast.ParamBlock
        $paramBlock.Parameters.Name.VariablePath.UserPath | Should -Contain "DryRun"
    }

    Context "Bitwarden Desktop installer asset pattern" {
        BeforeAll {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
            $assignment = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.VariablePath.UserPath -eq "BitwardenInstallerPattern"
            }, $true) | Select-Object -First 1
            $script:BitwardenPattern = $assignment.Right.Expression.Value
        }

        It "is declared as `$BitwardenInstallerPattern" {
            $BitwardenPattern | Should -Not -BeNullOrEmpty
        }

        # bitwarden/clients desktop-v2026.10.4 publishes the NSIS installer without an
        # arch suffix; the old "-x64" requirement matched nothing and the install threw.
        It "matches <Name>" -ForEach @(
            @{ Name = "Bitwarden-Installer-2026.10.4.exe" }
            @{ Name = "Bitwarden-Installer-2025.6.1-x64.exe" }
        ) {
            $Name | Should -Match $BitwardenPattern
        }

        It "rejects <Name>" -ForEach @(
            @{ Name = "Bitwarden-Installer-2026.10.4.exe.blockmap" }
            @{ Name = "Bitwarden-2026.10.4-x64.msi" }
            @{ Name = "Bitwarden-Portable-2026.10.4.exe" }
        ) {
            $Name | Should -Not -Match $BitwardenPattern
        }
    }
}
