#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# 
# bashclub zfs replication script
# Author: (C) 2025 Thorsten Spille <thorsten@spille-edv.de>

from argparse import Namespace
import os
import subprocess
import sys
import configparser
import shutil
from enum import Enum
from datetime import datetime

__version__ = "2.0-001"

class Severity (Enum):
    DEBUG = 7
    INFO = 6
    NOTICE = 5
    WARN = 4
    ERROR = 3
    CRITICAL = 2
    ALERT = 1
    EMERGENCY = 0

__loglevel: Severity = Severity.INFO

def log(message: str, severity: Severity) -> None:
    if severity.value <= __loglevel.value:
        print(f"{datetime.now().strftime('%Y-%m-%d %T %Z')} [{severity.name}] {message}")


def usage(exit_code=0):
    print(f"""
    bashclub-zsync.py Version {__version__}
    -------------------------------------------------------------------------------
    Usage: bashclub-zsync.py [-h] [-d] [-c CONFIG]
        Creates a mirrored replication of configured ZFS filesystems/volumes

        -c CONFIG    Configuration file for this script
        -d           Debug mode
    -------------------------------------------------------------------------------
    (C) 2024 by Spille IT Solutions for bashclub (github.com/bashclub)
    Author: Thorsten Spille <thorsten@spille-edv.de>
    -------------------------------------------------------------------------------
    """)
    sys.exit(exit_code)

def load_config(config_path) -> configparser.ConfigParser:
    config: dict  = {}
    if os.path.exists(config_path):
        log(f"Reading configuration {config_path}",Severity.INFO)
        with open(config_path) as file:
            for line in file:
                if line[0] != '#' and line[0] != '\n':
                    key, value= line.partition("=")[::2]
                    value = value.removesuffix('\n')
                    config[key] = value
    else:
        log(f"Config file {config_path} not found.", Severity.CRITICAL)
        usage(1)
    return config

def execute(command: str, failed_when: bool = False, debug: bool = False) -> str:
    if debug:
        log(f"Executing command: {command}", Severity.DEBUG)
    try:
        result: subprocess.CompletedProcess[str] = subprocess.run(command, shell=True, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        log(f"Command failed: {e}", Severity.ERROR)
        if failed_when:
          usage(e.returncode)

def check_command_availability(commands) -> dict:
    cmds: dict = {}
    for cmd in commands:
        log(f"Check command '{cmd}'...", Severity.DEBUG)
        try:
            cmdpath: str = shutil.which(cmd)
            log(f"Command '{cmd}' is located at '{cmdpath}'", Severity.DEBUG)
            cmds[cmd] = cmdpath
        except:
            log(f"Required command '{cmd}' not found.", Severity.ERROR)
            usage(1)
    
    return cmds

def main():
    import argparse

    parser = argparse.ArgumentParser(description="ZFS replication script in Python")
    parser.add_argument("-c", "--config", type=str, default="/etc/bashclub/zsync.conf", help="Path to config file")
    parser.add_argument("-d", "--debug", action="store_true", help="Enable debug mode")
    args: Namespace = parser.parse_args()

    config_path = args.config
    debug = args.debug
    local_mode: bool = False

    config: configparser.ConfigParser = load_config(config_path)

    # Extract configuration variables
    target: str = config.get("target", "pool/dataset")
    source: str = config.get("source", "user@host")
    if source == "":
        local_mode = True
    sshport: int = config.get("sshport", int(22))
    tag: str = config.get("tag", "bashclub:zsync")
    snapshot_filter: str = config.get("snapshot_filter", "hourly|daily|weekly|monthly")
    min_keep: int = config.get("min_keep", 3)

    cmds: dict = check_command_availability(["zfs", "ssh", "scp", "checkzfs" ])

    log(f"source: {source}, target: {target}, sshport: {sshport}, tag: {tag}, snapshot_filter: {snapshot_filter}, min_keep: {min_keep}", Severity.INFO)

    # Add logic for replication using ZFS and SSH commands

if __name__ == "__main__":
    main()
