#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright (C) 2018-2019 Richard Hughes <richard@hughsie.com>
# Copyright (C) 2020 Dave Olsthoorn <dave@bewaar.me>
#
# SPDX-License-Identifier: GPL-2.0+
#
# pylint: disable=arguments-differ,too-many-ancestors

import os
import re
import subprocess
from argparse import ArgumentParser
from codecs import (BOM_UTF8, BOM_UTF16_BE, BOM_UTF16_LE, BOM_UTF32_BE,
                    BOM_UTF32_LE)
from collections import OrderedDict
from distutils.spawn import find_executable
from pprint import pprint
from tempfile import mkdtemp
from typing import List
from datetime import datetime
import glob
import hashlib

BOM_MAPPINGS = [
    ('utf-8-sig', (BOM_UTF8,)),
    ('utf-32', (BOM_UTF32_LE, BOM_UTF32_BE)),
    ('utf-16', (BOM_UTF16_LE, BOM_UTF16_BE))
]

SCRIPT_PATH = os.path.realpath(__file__)
DIR_PATH = os.path.dirname(SCRIPT_PATH)
METAINFO_TEMPLATE_PATH = os.path.join(DIR_PATH, 'template.metainfo.xml')


"""
Version formats as supported by fwupd:
https://github.com/fwupd/fwupd/blob/e300ca513f812a053e7e262cc5d48150c152bd82/libfwupdplugin/fu-common-version.c#L77
"""
VERSION_FORMATS = {
    'plain': lambda version: "{}".format(
        version
    ),

    'pair': lambda version: "{}.{}".format(
        ((version >> 16) & 0xffff),
        (version & 0xffff)
    ),

    'triplet': lambda version: "{}.{}.{}".format(
        ((version >> 24) & 0xff),
        ((version >> 16) & 0xff),
        (version & 0xffff)
    ),

    'quad': lambda version: "{}.{}.{}.{}".format(
        ((version >> 24) & 0xff),
        ((version >> 16) & 0xff),
        ((version >> 8) & 0xff),
        (version & 0xff)
    ),

    'BCD': lambda version: "{}.{}.{}.{}".format(
        bcd(((version >> 24) & 0xff)),
        bcd(((version >> 16) & 0xff)),
        bcd(((version >> 8) & 0xff)),
        bcd((version & 0xff))
    ),

    'intel-me': lambda version: "{}.{}.{}.{}".format(
        (((version >> 29) & 0x07) + 0x0b),
        ((version >> 24) & 0x1f),
        ((version >> 16) & 0xff),
        (version & 0xffff)
    ),

    'intel-me2': lambda version: "{}.{}.{}.{}".format(
        ((version >> 28) & 0x0f),
        ((version >> 24) & 0x0f),
        ((version >> 16) & 0xff),
        (version & 0xffff)
    ),

    'surface-legacy': lambda version: "{}.{}.{}".format(
        ((version >> 22) & 0x3ff),
        ((version >> 10) & 0xfff),
        (version & 0x3ff)
    ),

    'surface': lambda version: "{}.{}.{}".format(
        ((version >> 24) & 0xff),
        ((version >> 8) & 0xffff),
        (version & 0xff)
    )
}


def bcd(val):
    return ((((val) >> 4) & 0x0f) * 10 + ((val) & 0x0f))


def detect_encoding(path, default='cp1252'):
    raw = b''
    with open(path, 'rb') as fh:
        raw = fh.read(4)

    for encoding, bom_list in BOM_MAPPINGS:
        if any(raw.startswith(bom) for bom in bom_list):
            return encoding
    return default


def get_files_by_ext(dir: str, ext: str):
    filenames = []
    for root, dirs, files in os.walk(args.dir):
        for filename in files:
            if filename.endswith(ext):
                filenames.append(os.path.join(root, filename))
    return filenames


EFI_GUID_REGEX = re.compile(
    r'Firmware_Install,\s*UEFI\\RES_\{(?P<uuid>[^\}]+)\}', re.I | re.M)
DRIVER_VER_REGEX = re.compile(
    r'DriverVer\s*=\s*(?P<date>[0-9]{2}/[0-9]{2}/[0-9]{4}),(?P<version>[^\s]+)', re.I | re.M)
FIRMWARE_VER_REGEX = re.compile(
    r'HKR,,FirmwareVersion,%REG_DWORD%,(?P<version>0x[A-F0-9]+)', re.I | re.M)
FIRMWARE_FILE_REGEX = re.compile(
    r'\[Firmware_CopyFiles\]\n(?P<firmware>[^\s]+)', re.I | re.M
)

def which(name: str) -> str:
    bin = find_executable(name)
    if bin:
        return bin
    raise ValueError('executable not found: {}'.format(name))

def get_category(name: str):
    if 'UEFI' in name:
        return 'X-System'
    if 'ME' in name:
        return 'X-ManagementEngine'
    return 'X-Device'


def get_hashes(path: str):
    # BUF_SIZE is totally arbitrary, change for your app!
    BUF_SIZE = 65536  # lets read stuff in 64kb chunks!

    sha256 = hashlib.sha256()
    sha1 = hashlib.sha1()

    with open(path, 'rb') as f:
        while True:
            data = f.read(BUF_SIZE)
            if not data:
                break
            sha256.update(data)
            sha1.update(data)
    return (sha1.hexdigest(), sha256.hexdigest())



def generate_cab(inf: str, model_name: str):
    inf_name = os.path.splitext(os.path.basename(inf))[0]
    with open(inf, 'r+', encoding=detect_encoding(inf)) as fh:
        inf_contents = fh.read()

        efi_guid_match = EFI_GUID_REGEX.search(inf_contents)
        driver_ver_match = DRIVER_VER_REGEX.search(inf_contents)
        fw_ver_match = FIRMWARE_VER_REGEX.search(inf_contents)
        fw_file_match = FIRMWARE_FILE_REGEX.search(inf_contents)

        if efi_guid_match and driver_ver_match and fw_ver_match:
            efi_guid = efi_guid_match.group('uuid').lower()
            driver_ver = driver_ver_match.group('version')
            driver_date = datetime.strptime(
                driver_ver_match.group('date'), '%m/%d/%Y')
            fw_ver = int(fw_ver_match.group('version'), 16)
            fw_file = fw_file_match.group('firmware')

            fw_file_sha1, fw_file_sha256 = get_hashes(
                os.path.join(
                    os.path.dirname(inf),
                    fw_file
                )
            )

            ver_fmt = None

            for version_fmt_name, version_fmt in VERSION_FORMATS.items():
                if version_fmt(fw_ver) in driver_ver:
                    ver_fmt = version_fmt_name

            if ver_fmt is None:
                print('SKIP: No version format', fw_ver, driver_ver)
                return

            metainfo = open(METAINFO_TEMPLATE_PATH, 'r').read().format(
                UEFIVER=fw_ver,
                VERSIONFMT=ver_fmt,
                TIMESTAMP=int(driver_date.timestamp()),
                CATEGORY=get_category(inf_name),
                MODELFMT=inf_name,
                MODEL=model_name,
                MSVER=driver_ver,
                DEVICE=efi_guid,
                FIRMWARE=inf_name,
                FWFILE=fw_file,
                FWSHA1=fw_file_sha1,
                FWSHA256=fw_file_sha256
            )

            metainfo_path = os.path.join(
                os.path.dirname(inf),
                "{}.metainfo.xml".format(inf_name)
            )

            with open(metainfo_path, 'w+') as mh:
                mh.write(metainfo)

            gcab = which('gcab')
            args = [
                gcab,
                '-cn',
                os.path.join(DIR_PATH, 'output/{}_{}.cab'.format(inf_name, fw_ver))
            ]

            args.extend(glob.glob(os.path.join(os.path.dirname(inf), '*')))
            subprocess.run(args)
        else:
            print(efi_guid_match, driver_ver_match, fw_ver_match)


def unpack_msi(msi: str):
    tmpd = mkdtemp()
    msi_extract = which('msiextract')
    subprocess.run([
        msi_extract,
        '-C',
        tmpd,
        msi
    ])


parser = ArgumentParser()
filename_group = parser.add_mutually_exclusive_group()
filename_group.add_argument('-i', '--inf')
filename_group.add_argument('-d', '--dir')
filename_group.add_argument('-m', '--msi')

args = parser.parse_args()

model_name = 'Surface Pro (2017)'

if args.inf:
    inf = args.inf
    generate_cab(inf, model_name)

elif args.dir:
    dir = args.dir
    for inf in get_files_by_ext(dir, '.inf'):
        generate_cab(inf, model_name)

elif args.msi:
    msi = args.msi
    dir = unpack_msi(msi)
    for inf in get_files_by_ext(dir, '.inf'):
        generate_cab(inf, model_name)

else:
    print('no argument given')
