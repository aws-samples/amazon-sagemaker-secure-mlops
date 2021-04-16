# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import json
import boto3
import cfnresponse
from botocore.exceptions import ClientError

sm = boto3.client("sagemaker")

def lambda_handler(event, context):
    try:
        response_status = cfnresponse.SUCCESS
        r = {}

        if 'RequestType' in event and event['RequestType'] == 'Create':
            r["SageMakerDomainId"] = sm.describe_project(
                ProjectName=event["ResourceProperties"]["SageMakerProjectName"]
                )["CreatedBy"]["DomainId"]

        print(r)
        cfnresponse.send(event, context, response_status, r, '')

    except ClientError as exception:
        print(exception)
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physicalResourceId=event.get('PhysicalResourceId'), reason=str(exception))
