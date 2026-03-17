#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

SENSITIVE_KEYS = {
    "KEYCLOAK_PASSWORD",
    "TF_VAR_forward_auth_client_secret",
}


def parse_dotenv(dotenv_path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not dotenv_path.exists():
        return values

    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("export "):
            line = line[7:].lstrip()

        if "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if not key:
            continue

        if value[:1] in {'"', "'"} and value[-1:] == value[:1]:
            value = value[1:-1]
        elif " #" in value:
            value = value.split(" #", 1)[0].rstrip()

        values[key] = value

    return values


def first_non_empty(*values: str | None) -> str | None:
    for value in values:
        if value is not None and value != "":
            return value
    return None


def resolve_env(
    current_env: dict[str, str], dotenv_values: dict[str, str]
) -> dict[str, str]:
    resolved = dict(current_env)

    defaults = {
        "KEYCLOAK_URL": first_non_empty(
            current_env.get("KEYCLOAK_URL"),
            dotenv_values.get("KEYCLOAK_URL"),
            "https://keycloak.localtest.me",
        ),
        "KEYCLOAK_CLIENT_ID": first_non_empty(
            current_env.get("KEYCLOAK_CLIENT_ID"),
            dotenv_values.get("KEYCLOAK_CLIENT_ID"),
            "admin-cli",
        ),
        "KEYCLOAK_USER": first_non_empty(
            current_env.get("KEYCLOAK_USER"),
            dotenv_values.get("KEYCLOAK_USER"),
            # Allow KEYCLOAK_ADMIN as a fallback for backward compatibility with older .env files
            dotenv_values.get("KEYCLOAK_ADMIN"),
        ),
        "KEYCLOAK_PASSWORD": first_non_empty(
            current_env.get("KEYCLOAK_PASSWORD"),
            dotenv_values.get("KEYCLOAK_PASSWORD"),
            # Allow KEYCLOAK_ADMIN_PASSWORD as a fallback for backward compatibility with older .env files
            dotenv_values.get("KEYCLOAK_ADMIN_PASSWORD"),
        ),
        "KEYCLOAK_REALM": first_non_empty(
            current_env.get("KEYCLOAK_REALM"),
            dotenv_values.get("KEYCLOAK_PROVIDER_REALM"),
            "master",
        ),
        "TF_VAR_realm_name": first_non_empty(
            current_env.get("TF_VAR_realm_name"),
            dotenv_values.get("TF_VAR_realm_name"),
            dotenv_values.get("KEYCLOAK_REALM"),
            "default",
        ),
        "TF_VAR_forward_auth_client_id": first_non_empty(
            current_env.get("TF_VAR_forward_auth_client_id"),
            dotenv_values.get("TF_VAR_forward_auth_client_id"),
            dotenv_values.get("KEYCLOAK_FORWARD_AUTH_CLIENT_ID"),
            "traefik-forward-auth",
        ),
        "TF_VAR_forward_auth_client_secret": first_non_empty(
            current_env.get("TF_VAR_forward_auth_client_secret"),
            dotenv_values.get("TF_VAR_forward_auth_client_secret"),
            dotenv_values.get("KEYCLOAK_FORWARD_AUTH_CLIENT_SECRET"),
        ),
        "TF_VAR_forward_auth_client_secret_version": first_non_empty(
            current_env.get("TF_VAR_forward_auth_client_secret_version"),
            dotenv_values.get("TF_VAR_forward_auth_client_secret_version"),
            dotenv_values.get("KEYCLOAK_FORWARD_AUTH_CLIENT_SECRET_VERSION"),
            "1",
        ),
        "TF_VAR_forward_auth_root_url": first_non_empty(
            current_env.get("TF_VAR_forward_auth_root_url"),
            dotenv_values.get("TF_VAR_forward_auth_root_url"),
            "https://auth.localtest.me",
        ),
        "TF_VAR_forward_auth_redirect_uri": first_non_empty(
            current_env.get("TF_VAR_forward_auth_redirect_uri"),
            dotenv_values.get("TF_VAR_forward_auth_redirect_uri"),
            "https://auth.localtest.me/_oauth",
        ),
    }

    for key, value in defaults.items():
        if value is not None:
            resolved[key] = value

    return resolved


def validate_env(resolved_env: dict[str, str]) -> list[str]:
    required_keys = [
        "KEYCLOAK_URL",
        "KEYCLOAK_CLIENT_ID",
        "KEYCLOAK_USER",
        "KEYCLOAK_PASSWORD",
        "KEYCLOAK_REALM",
        "TF_VAR_realm_name",
        "TF_VAR_forward_auth_client_id",
        "TF_VAR_forward_auth_client_secret",
        "TF_VAR_forward_auth_client_secret_version",
        "TF_VAR_forward_auth_root_url",
        "TF_VAR_forward_auth_redirect_uri",
    ]
    return [key for key in required_keys if not resolved_env.get(key)]


def format_value(key: str, value: str | None) -> str:
    if value is None:
        return "<unset>"
    if key in SENSITIVE_KEYS:
        return "********"
    return value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Read ../../.env, set Terraform defaults, and run terraform plan or apply.",
    )
    parser.add_argument(
        "terraform_command",
        nargs="?",
        choices=("plan", "apply"),
        default="plan",
        help="Terraform subcommand to run. Defaults to 'plan'.",
    )
    parser.add_argument(
        "--terraform-bin",
        default=os.environ.get("TERRAFORM_BIN", "terraform"),
        help="Terraform executable to run. Defaults to 'terraform'.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the resolved environment and command without executing terraform.",
    )
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args, terraform_args = parser.parse_known_args(argv)

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    dotenv_path = repo_root / ".env"

    dotenv_values = parse_dotenv(dotenv_path)
    resolved_env = resolve_env(dict(os.environ), dotenv_values)
    missing_keys = validate_env(resolved_env)

    if missing_keys:
        print("Missing required Terraform environment values:", file=sys.stderr)
        for key in missing_keys:
            print(f"- {key}", file=sys.stderr)
        print(file=sys.stderr)
        print(f"Checked .env at {dotenv_path}", file=sys.stderr)
        return 1

    terraform_command = [args.terraform_bin, args.terraform_command, *terraform_args]

    print(f"Using .env: {dotenv_path}")
    print(f"Working directory: {script_dir}")
    print("Resolved Terraform defaults:")
    for key in [
        "KEYCLOAK_URL",
        "KEYCLOAK_CLIENT_ID",
        "KEYCLOAK_USER",
        "KEYCLOAK_PASSWORD",
        "KEYCLOAK_REALM",
        "TF_VAR_realm_name",
        "TF_VAR_forward_auth_client_id",
        "TF_VAR_forward_auth_client_secret",
        "TF_VAR_forward_auth_client_secret_version",
        "TF_VAR_forward_auth_root_url",
        "TF_VAR_forward_auth_redirect_uri",
    ]:
        print(f"  {key}={format_value(key, resolved_env.get(key))}")

    print("Command:")
    print("  " + " ".join(terraform_command))

    if args.dry_run:
        return 0

    try:
        completed = subprocess.run(
            terraform_command,
            cwd=script_dir,
            env=resolved_env,
            check=False,
        )
    except FileNotFoundError:
        print(f"Terraform executable not found: {args.terraform_bin}", file=sys.stderr)
        return 1

    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
