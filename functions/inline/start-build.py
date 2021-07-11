# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import json
import boto3
import cfnresponse

cb = boto3.client("codebuild")

def lambda_handler(event, context):
    try:
        response_status = cfnresponse.SUCCESS

        if 'RequestType' in event and event['RequestType'] == 'Create':
            cb.start_build(projectName=event['ResourceProperties']['ProjectName'])
            
        cfnresponse.send(event, context, response_status, {}, '')

    except Exception as e:
        print(str(e))
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physicalResourceId=event.get('PhysicalResourceId'), reason=str(e))
