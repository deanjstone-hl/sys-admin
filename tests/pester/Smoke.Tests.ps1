# Confirms the Pester scaffold itself is wired up correctly.
# Per deanjstone/sys-admin#15, substantive script coverage lands in #20 —
# this file and the per-script smoke tests alongside it just prove the
# framework runs, not that the scripts are fully covered.

Describe "Pester scaffold" {
    It "runs and reports success" {
        $true | Should -Be $true
    }

    It "reports failure correctly" {
        { throw "expected failure" } | Should -Throw
    }
}
