#!/usr/bin/env python3

import argparse
import sys
import os.path
import json
import re
import subprocess

import tempfile
import shutil
import zipfile

all_roles = {}

parser = argparse.ArgumentParser(description='Deploy Lambdas to AWS')

parser.add_argument('zipfile',metavar='zipfile', help='Zipfile for compiled lambda')
parser.add_argument('resources',metavar='resources', help='resources.conf.json file to deploy to')
parser.add_argument('--force', action='store_true', help='Force deploy')

args = parser.parse_args()

input_zip = args.zipfile
resources_file = args.resources
force = args.force

def remove_from_zip(zipfname, *filenames):
    tempdir = tempfile.mkdtemp()
    try:
        tempname = os.path.join(tempdir, 'new.zip')
        with zipfile.ZipFile(zipfname, 'r') as zipread:
            with zipfile.ZipFile(tempname, 'w') as zipwrite:
                for item in zipread.infolist():
                    if item.filename not in filenames:
                        data = zipread.read(item.filename)
                        zipwrite.writestr(item, data)
        shutil.move(tempname, zipfname)
    finally:
        shutil.rmtree(tempdir)

def main():

  temp_dir = tempfile.mkdtemp()
  target_zip = os.path.join(temp_dir, os.path.basename(input_zip))
  shutil.copy2(input_zip, target_zip)

  resource_data = {}
  if os.path.isfile(resources_file):
    with open(resources_file) as f:
      all_resource_data = json.load(f)
      resource_data = all_resource_data['functions']
      region = all_resource_data['region']
  else:
    print('Could not find resources file')
    sys.exit(1)

  function_name = os.path.basename(input_zip).split('-')[0]
  new_version = os.path.splitext('-'.join(os.path.basename(input_zip).split('-')[1:]))[0]
  function_id = resource_data[function_name]

  # No way to overwrite existing files in 
  # zip in python, so we should just remove file

  remove_from_zip(target_zip,'resources.conf.json')

  zip = zipfile.ZipFile(target_zip,'a')
  zip.write(resources_file,'resources.conf.json')
  zip.close()


  function_configuration_resp = subprocess.check_output(['aws','lambda','get-function-configuration','--region',region,'--function-name', function_id ])
  function_configuration = json.loads(function_configuration_resp.decode('utf8'))
  current_version = function_configuration['Description']

  if current_version == new_version and not 'dirty' in current_version and not force:
    print("Versions match, exiting")
    sys.exit(0)

  subprocess.check_output(['aws','lambda','update-function-code','--region',region,'--function-name', function_id, '--zip-file', 'fileb://{}'.format(target_zip) ])
  subprocess.check_output(['aws','lambda','update-function-configuration','--region',region,'--function-name', function_id, '--description' , new_version ])

  print('Updated {} to version {}'.format(function_id,new_version))

main()