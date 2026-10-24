#!/usr/bin/env python3
"""Offline docker compose security contract for the VagaDeck private OIDC rehearsal."""

from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
COMPOSE = ROOT / "compose.yaml"
DOCKERFILE = ROOT / "Dockerfile.keycloak"


class PrivateOidcComposeContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Docker Desktop CLI is Windows-native when WSL integration is disabled.
        is_wsl = bool(os.environ.get('WSL_DISTRO_NAME'))
        cls.tmp = tempfile.TemporaryDirectory(prefix='vagadeck-oidc-contract-', dir=ROOT if is_wsl else None)
        private = Path(cls.tmp.name)
        def docker_path(path):
            if not is_wsl:
                return str(path)
            return subprocess.check_output(['wslpath', '-w', str(path)], text=True).strip()
        docker_bin = 'docker.exe' if is_wsl else 'docker'
        envfile = private / "keycloak.env"
        dbfile = private / "postgres.env"
        keystore = private / "keycloak.p12"
        dbfile.write_text('POSTGRES_PASSWORD=synthetic-no-secret\n', encoding='utf-8')
        envfile.write_text(
            "KC_DB_PASSWORD=synthetic-no-secret\n"
            "KC_HOSTNAME=https://localhost:19443\n"
            "KC_BOOTSTRAP_ADMIN_USERNAME=synthetic-test\n"
            "KC_BOOTSTRAP_ADMIN_PASSWORD=synthetic-no-secret\n"
            "KC_HTTPS_KEY_STORE_PASSWORD=synthetic-no-secret\n",
            encoding="utf-8",
        )
        keystore.write_bytes(b"dummy-keystore-used-for-static-config-only")
        compose_params = private / 'compose-params.env'
        compose_params.write_text(
            'VAGADECK_OIDC_KEYCLOAK_CONFIG_FILE=' + docker_path(envfile) + '\n'
            + 'VAGADECK_OIDC_DB_CONFIG_FILE=' + docker_path(dbfile) + '\n'
            + 'VAGADECK_OIDC_KEYSTORE_FILE=' + docker_path(keystore) + '\n',
            encoding='utf-8',
        )
        env = os.environ.copy()
        env.update(
            {
                "VAGADECK_OIDC_KEYCLOAK_CONFIG_FILE": docker_path(envfile),
                "VAGADECK_OIDC_DB_CONFIG_FILE": docker_path(dbfile),
                "VAGADECK_OIDC_KEYSTORE_FILE": docker_path(keystore),
            }
        )
        result = subprocess.run(
            [docker_bin, 'compose', '--env-file', docker_path(compose_params), '-f', docker_path(COMPOSE), 'config', '--format', 'json'],
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            raise AssertionError('Docker Compose config rejected synthetic fixtures: ' + (result.stderr or result.stdout)[-1500:])
        cls.stack = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_project_has_only_idp_and_dedicated_postgres(self):
        self.assertEqual(self.stack.get("name"), "vagadeck-oidc-private")
        self.assertEqual(set(self.stack["services"]), {"keycloak", "postgres"})

    def test_database_has_no_published_ports(self):
        self.assertFalse(self.stack["services"]["postgres"].get("ports"))

    def test_all_published_keycloak_ports_bind_loopback(self):
        ports = self.stack["services"]["keycloak"]["ports"]
        self.assertEqual({p["target"] for p in ports}, {8443, 9000})
        self.assertEqual({p.get("host_ip") for p in ports}, {"127.0.0.1"})

    def test_database_network_is_internal(self):
        networks = self.stack["networks"]
        self.assertTrue(networks["db-private"]["internal"])

    def test_postgres_never_joins_external_network(self):
        networks = self.stack["services"]["postgres"]["networks"]
        self.assertEqual(set(networks), {"db-private"})

    def test_keycloak_uses_separate_external_and_internal_networks(self):
        self.assertEqual(
            set(self.stack["services"]["keycloak"]["networks"]),
            {"db-private", "frontend-private"},
        )

    def test_db_uses_dedicated_named_volume(self):
        mounts = self.stack["services"]["postgres"]["volumes"]
        self.assertTrue(
            any(m.get("type") == "volume" and m.get("target") == "/var/lib/postgresql/data" for m in mounts)
        )
        self.assertNotIn("postgres", {m.get("type") for m in mounts})

    def test_keycloak_is_optimized_prod_mode_with_no_http(self):
        keycloak = self.stack["services"]["keycloak"]
        self.assertEqual(keycloak["command"][0:2], ["start", "--optimized"])
        self.assertIn("--http-enabled=false", keycloak["command"])
        self.assertIn("--hostname-strict=true", keycloak["command"])
        self.assertEqual(keycloak["environment"]["KC_HTTP_ENABLED"], "false")
        self.assertEqual(keycloak["environment"]["KC_DB"], "postgres")

    def test_tls_keystore_is_bind_mounted_read_only(self):
        volumes = self.stack["services"]["keycloak"]["volumes"]
        keys = [m for m in volumes if m.get("target") == "/opt/keycloak/conf/tls/keycloak.p12"]
        self.assertEqual(len(keys), 1)
        self.assertEqual(keys[0]["type"], "bind")
        self.assertTrue(keys[0]["read_only"])

    def test_keycloak_db_dependency_uses_healthcheck(self):
        self.assertEqual(
            self.stack["services"]["keycloak"]["depends_on"]["postgres"]["condition"],
            "service_healthy",
        )

    def test_postgres_has_no_development_h2_config(self):
        self.assertEqual(self.stack["services"]["postgres"]["environment"]["POSTGRES_DB"], "keycloak")
        self.assertEqual(
            self.stack["services"]["keycloak"]["environment"]["KC_DB_URL"],
            "jdbc:postgresql://postgres:5432/keycloak",
        )

    def test_dockerfile_pins_keycloak_and_optimizes(self):
        text = DOCKERFILE.read_text(encoding="utf-8")
        self.assertEqual(text.count("FROM quay.io/keycloak/keycloak:26.4.2@sha256:"), 2)
        self.assertIn("RUN /opt/keycloak/bin/kc.sh build", text)
        self.assertIn("KC_HEALTH_ENABLED=true", text)
        self.assertNotIn("start-dev", text)

    def test_no_secrets_or_staging_admin_baked_in(self):
        text = DOCKERFILE.read_text(encoding="utf-8")
        for forbidden in ("BOOTSTRAP_ADMIN_PASSWORD", "KC_DB_PASSWORD=", "COPY keycloak.p12"):
            self.assertNotIn(forbidden, text)

    def test_database_never_receives_keycloak_admin_secret(self):
        postgres = self.stack['services']['postgres']['environment']
        self.assertNotIn('KC_BOOTSTRAP_ADMIN_PASSWORD', postgres)
        self.assertNotIn('KC_HTTPS_KEY_STORE_PASSWORD', postgres)

    def test_keycloak_receives_no_postgres_init_secret(self):
        keycloak = self.stack['services']['keycloak']['environment']
        self.assertNotIn('POSTGRES_PASSWORD', keycloak)
        self.assertEqual(keycloak['KC_DB_PASSWORD'], 'synthetic-no-secret')

    def test_no_host_wide_bindings_or_proxy_passthrough(self):
        content = COMPOSE.read_text(encoding="utf-8")
        self.assertNotIn("0.0.0.0:", content)
        self.assertNotIn("KC_PROXY_HEADERS", content)
        self.assertNotIn("docker.sock", content)


if __name__ == "__main__":
    unittest.main()
