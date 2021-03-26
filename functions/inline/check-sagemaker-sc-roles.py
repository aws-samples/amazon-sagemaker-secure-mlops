# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import json
import boto3
import cfnresponse
from botocore.exceptions import ClientError

iam = boto3.client('iam')

def lambda_handler(event, context):
    try:
        response_status = cfnresponse.SUCCESS
        r = {}

        if 'RequestType' in event and event['RequestType'] == 'Create':
            r = check_roles(event['ResourceProperties']['RoleNames'])

        cfnresponse.send(event, context, response_status, r, '')

    except ClientError as exception:
        print(exception)
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physicalResourceId=event.get('PhysicalResourceId'), reason=str(exception))

def check_roles(roles):
    ret = {}
    for r in roles:
        try:
            iam.get_role(RoleName=r)
            ret[r] = ""
        except iam.exceptions.NoSuchEntityException:
            ret[r] = r

    return ret