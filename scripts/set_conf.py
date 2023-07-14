#!/usr/bin/env python3
import ast
import uuid
import yaml

from argparse import ArgumentParser, Namespace
from io import StringIO
from typing import Any, Dict


def parse_args() -> Namespace:
    parser = ArgumentParser()
    parser.add_argument("-f", "--file", help="configuration file path")
    parser.add_argument("-k", "--key", help="the config key to set")
    parser.add_argument("-v", "--value", help="value of the config entry to set")
    return parser.parse_args()


def load(name: str) -> Dict[str, Any]:
    with open(name, mode="r") as f:
        lines = f.read().splitlines()

        # when the yaml doc is empty, parser has no way of knowing it's a yaml doc
        random_id = uuid.uuid4().hex
        lines.append(f"{random_id}: {random_id}")

        yaml_doc = yaml.safe_load(StringIO("\n".join(lines)))
        del yaml_doc[random_id]

        return yaml_doc


def write(name: str, yaml_doc: Dict[str, Any]) -> None:
    with open(name, mode="w") as f:
        yaml.dump(yaml_doc, f)


if __name__ == "__main__":
    args = parse_args()

    data = load(args.file)

    print(args.value)

    if args.value.startswith("[") and args.value.endswith("]"):
        data[args.key] = ast.literal_eval(args.value)
    else:
        data[args.key] = args.value

    write(args.file, data)
