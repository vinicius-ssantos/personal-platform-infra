"""Offline safety checks for VagaDeck's local PostgreSQL recovery drill.

These static checks do not contact Docker or exercise an actual restore.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent
SCRIPT = ROOT / "verify-backup-restore.ps1"


class RecoveryDrillContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = SCRIPT.read_text(encoding="utf-8")
        cls.clean = re.sub(r"(?m)^\s*#.*$", "", cls.script)

    def test_requires_explicit_local_lab_confirmation(self):
        self.assertIn("[switch]$ConfirmIsolatedLocalLab", self.script)
        self.assertIn("if (-not $ConfirmIsolatedLocalLab)", self.script)

    def test_fixed_user_local_secret_paths(self):
        self.assertIn("$env:LOCALAPPDATA", self.script)
        self.assertIn("VagaDeck\\keycloak-prod-rehearsal", self.script)
        self.assertIn("postgres.env", self.script)
        self.assertIn("keycloak.env", self.script)

    def test_requires_localhost_issuer(self):
        self.assertIn("KC_HOSTNAME=https://localhost:19443", self.script)
        self.assertIn("unexpected image", self.script)

    def test_checks_compose_project_and_postgres_service(self):
        self.assertIn("'vagadeck-oidc-private'", self.script)
        self.assertIn("'com.docker.compose.project'", self.script)
        self.assertIn("'com.docker.compose.service'", self.script)

    def test_pins_postgres_17_image_and_source_volume(self):
        self.assertRegex(self.script, r"postgres:17-alpine@sha256:[0-9a-f]{64}")
        self.assertIn("vagadeck-oidc-private_postgres-data", self.script)
        self.assertIn("/var/lib/postgresql/data", self.script)

    def test_fails_closed_if_source_exposes_a_port(self):
        self.assertIn(".HostConfig.PortBindings", self.script)
        self.assertIn("$bindings -ne '{}'", self.script)

    def test_archive_uses_binary_safe_custom_format(self):
        self.assertIn("'pg_dump', '--format=custom'", self.script)
        self.assertIn("'--file', $sourceDump", self.script)
        self.assertIn("'cp', \"${sourceId}:$sourceDump\"", self.script)
        self.assertNotRegex(self.clean, r"(?i)pg_dump[^\n]*\s+>\s+")

    def test_scratch_restore_disconnected_with_no_ports(self):
        self.assertIn("'--network', 'none'", self.script)
        self.assertIn("$scratchNetwork -ne 'none'", self.script)
        self.assertIn("$scratchPorts -ne '{}'", self.script)
        self.assertNotIn("'--publish'", self.clean)

    def test_backup_uses_acl_and_sha256(self):
        self.assertIn("icacls $backupDir", self.script)
        self.assertIn("icacls $localDump", self.script)
        self.assertIn("Get-FileHash -LiteralPath $localDump -Algorithm SHA256", self.script)

    def test_restore_exits_on_error_and_is_atomic(self):
        self.assertIn("'pg_restore', '--exit-on-error', '--single-transaction'", self.script)
        self.assertIn("'--no-owner', '--no-acl'", self.script)
        self.assertIn("'pg_restore', '--list'", self.script)

    def test_verifies_realms_and_table_counts(self):
        self.assertIn("SELECT COUNT(*) FROM realm", self.script)
        self.assertIn("information_schema.tables", self.script)
        self.assertIn("$sourceRealms -ne $scratchRealms", self.script)
        self.assertIn("$sourceTables -ne $scratchTables", self.script)

    def test_always_cleans_scratch_and_temp_dump(self):
        self.assertIn("} finally {", self.script)
        tail = self.script.split("} finally {")[-1]
        self.assertIn("docker rm --force $scratch", tail)
        self.assertIn("docker exec $sourceId rm -f -- $sourceDump", tail)
        self.assertIn("Remove-Item -LiteralPath $localDump -Force", tail)

    def test_never_issues_destructive_sql_against_source(self):
        for forbidden in (
            "DROP DATABASE", "TRUNCATE", "DELETE FROM", "ALTER ROLE",
            "'down'", "'--volumes'", "'pg_restore', $sourceId",
        ):
            self.assertNotIn(forbidden, self.clean)

    def test_does_not_print_temporary_password(self):
        self.assertIn("'--env', 'POSTGRES_PASSWORD'", self.script)
        self.assertNotRegex(self.clean, r"(?i)Write-Output\s+\$env:POSTGRES_PASSWORD")
        self.assertIn(
            "[Environment]::SetEnvironmentVariable('POSTGRES_PASSWORD', $priorPgPassword, 'Process')",
            self.script,
        )

    def test_archive_retention_is_opt_in(self):
        self.assertIn("[switch]$KeepBackup", self.script)
        self.assertIn("-not $KeepBackup -or -not $verified", self.script)
        self.assertIn("sensitive unencrypted local backup", self.script)


if __name__ == "__main__":
    unittest.main()
