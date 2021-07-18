# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import time
import boto3
import logging
import cfnresponse
from botocore.exceptions import ClientError

sm_client = boto3.client('sagemaker')
logger = logging.getLogger(__name__)

def delete_apps(domain_id):    
    logging.info(f'Start deleting apps for domain id: {domain_id}')

    try:
        sm_client.describe_domain(DomainId=domain_id)
    except:
        logging.info(f'Cannot retrieve {domain_id}')
        return

    for p in sm_client.get_paginator('list_apps').paginate(DomainIdEquals=domain_id):
        for a in p['Apps']:
            if a['AppType'] == 'KernelGateway' and a['Status'] != 'Deleted':
                sm_client.delete_app(DomainId=a['DomainId'], UserProfileName=a['UserProfileName'], AppType=a['AppType'], AppName=a['AppName'])
        
    apps = 1
    while apps:
        apps = 0
        for p in sm_client.get_paginator('list_apps').paginate(DomainIdEquals=domain_id):
            apps += len([a['AppName'] for a in p['Apps'] if a['AppType'] == 'KernelGateway' and a['Status'] != 'Deleted'])
        logging.info(f'Number of active KernelGateway apps: {str(apps)}')
        time.sleep(5)

    logger.info(f'KernelGateway apps for {domain_id} deleted')
    return

def handler(event, context):
    response_data = {}
    physicalResourceId = event.get('PhysicalResourceId')

    try:
        if event['RequestType'] in ['Create', 'Update']:
            physicalResourceId = event.get('ResourceProperties')['DomainId']
   
        elif event['RequestType'] == 'Delete':        
            delete_apps(physicalResourceId)

        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physicalResourceId=physicalResourceId)

    except ClientError as exception:
        logging.error(exception)
        cfnresponse.send(event, context, cfnresponse.FAILED, response_data, physicalResourceId=physicalResourceId, reason=str(exception))