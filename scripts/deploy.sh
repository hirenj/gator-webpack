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
import datetime

all_roles = {}

parser = argparse.ArgumentParser(description='Deploy Lambdas to AWS')

parser.add_argument('zipfile',metavar='zipfile', nargs='?', help='Zipfile for compiled lambda')
parser.add_argument('resources',metavar='resources', nargs='?', help='resources.conf.json file to deploy to')
parser.add_argument('--print-resources', action='store_true', help='Print resources.conf.json')
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

def combine_resources(resources):

  resource_keys = {
    'AWS::Lambda::Function': 'functions',
    'AWS::S3::Bucket' : 'buckets',
    'AWS::DynamoDB::Table' : 'tables',
    'AWS::StepFunctions::StateMachine' : 'stepfunctions',
    'AWS::SQS::Queue' : 'queue',
    'AWS::Events::Rule' : 'rule'
  }
  results = {
    'functions' : {},
    'buckets' : {},
    'tables' : {},
    'stepfunctions' : {},
    'queue' : {},
    'rule'  : {}
  }

  for resource in resources:
    if resource['ResourceType'] in resource_keys:
      wanted_key = resource_keys[ resource['ResourceType'] ]
      results[wanted_key][ resource['LogicalResourceId'] ] = resource['PhysicalResourceId']

  results['stack'] = os.environ['STACK']
  results['timestamp'] = datetime.datetime.now().isoformat()

  return results

def get_stack_resources(stack):
  json_text = subprocess.check_output(['aws','cloudformation','list-stack-resources','--region',os.environ['AWS_REGION'],'--stack-name', os.environ['STACK'] ])
  return combine_resources(json.loads(json_text.decode('utf8'))['StackResourceSummaries'])

def main():

  if resources_file is None and 'STACK' not in os.environ and 'AWS_REGION' not in os.environ:
    print("Missing resources file or environment variables STACK and AWS_REGION")
    parser.print_help()
    sys.exit(1)

  if input_zip is None and args.print_resources:
    print(json.dumps(get_stack_resources(os.environ['STACK'])))
    sys.exit(0)

  if input_zip is None:
    parser.print_help()
    sys.exit(1)

  temp_dir = tempfile.mkdtemp()
  target_zip = os.path.join(temp_dir, os.path.basename(input_zip))
  shutil.copy2(input_zip, target_zip)

  resource_data = {}
  local_resource_file = resources_file

  if local_resource_file is not None and os.path.isfile(local_resource_file):
    with open(local_resource_file) as f:
      all_resource_data = json.load(f)
      resource_data = all_resource_data['functions']
      region = all_resource_data['region']
  else:
    all_resource_data = get_stack_resources(os.environ['STACK'])
    region = os.environ['AWS_REGION']
    resource_data = all_resource_data['functions']
    local_resource_file = os.path.join(temp_dir, 'resources.conf.json')
    with open(local_resource_file, 'w') as f:
      json.dump(all_resource_data, f)

  function_name = os.path.basename(input_zip).split('-')[0]
  new_version = os.path.splitext('-'.join(os.path.basename(input_zip).split('-')[1:]))[0]
  function_id = resource_data[function_name]

  # No way to overwrite existing files in 
  # zip in python, so we should just remove file

  remove_from_zip(target_zip,'resources.conf.json')

  zip = zipfile.ZipFile(target_zip,'a')
  zip.write(local_resource_file,'resources.conf.json')
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