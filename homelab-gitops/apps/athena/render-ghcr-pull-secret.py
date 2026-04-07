#!/usr/bin/env python3

import argparse
import base64
import json
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a GHCR image pull Secret manifest for ATHENA."
    )
    parser.add_argument(
        "--token-file",
        required=True,
        help="Path to a file containing a GitHub PAT with read:packages scope.",
    )
    parser.add_argument(
        "--username",
        default="ixxet",
        help="GHCR username. Defaults to ixxet.",
    )
    parser.add_argument(
        "--namespace",
        default="athena",
        help="Kubernetes namespace. Defaults to athena.",
    )
    parser.add_argument(
        "--secret-name",
        default="athena-ghcr-pull",
        help="Secret name. Defaults to athena-ghcr-pull.",
    )
    return parser.parse_args()


def read_token(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        token = handle.read().strip()

    if not token:
        raise ValueError(f"token file is empty: {path}")

    return token


def render_secret(username: str, token: str, namespace: str, secret_name: str) -> str:
    auth = base64.b64encode(f"{username}:{token}".encode("utf-8")).decode("ascii")
    docker_config = {
        "auths": {
            "ghcr.io": {
                "username": username,
                "password": token,
                "auth": auth,
            }
        }
    }

    docker_config_json = json.dumps(docker_config, separators=(",", ":"))

    return "\n".join(
        [
            "apiVersion: v1",
            "kind: Secret",
            "metadata:",
            f"  name: {secret_name}",
            f"  namespace: {namespace}",
            "type: kubernetes.io/dockerconfigjson",
            "stringData:",
            "  .dockerconfigjson: |",
            *[f"    {line}" for line in docker_config_json.splitlines()],
            "",
        ]
    )


def main() -> int:
    args = parse_args()
    try:
        token = read_token(args.token_file)
    except OSError as error:
        print(f"failed to read token file: {error}", file=sys.stderr)
        return 1
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1

    sys.stdout.write(
        render_secret(
            username=args.username,
            token=token,
            namespace=args.namespace,
            secret_name=args.secret_name,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
