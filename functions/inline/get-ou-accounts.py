# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import json
import boto3
import cfnresponse
from botocore.exceptions import ClientError

org_client = boto3.client("organizations")


def lambda_handler(event, context):
    try:
        response_status = cfnresponse.SUCCESS
        r = {}

        if 'RequestType' in event and event['RequestType'] == 'Create':
            r["Accounts"] = get_ou_accounts(
                event['ResourceProperties']['OUIds']
            )

        cfnresponse.send(event, context, response_status, r, '')

    except ClientError as exception:
        print(exception)
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physicalResourceId=event.get('PhysicalResourceId'), reason=str(exception))

# This operation can be called only from the organization's management account or by a member account that is a delegated administrator for an AWS service
def get_ou_accounts(ou_ids):
    accounts = []
    for ou_id in ou_ids:
        accounts += ([a for a in [i['Id'] for i in org_client.list_accounts_for_parent(ParentId=ou_id)['Accounts']]])

    return accounts
