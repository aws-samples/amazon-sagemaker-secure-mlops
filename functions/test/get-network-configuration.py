# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import json
import boto3
import cfnresponse
from botocore.exceptions import ClientError

ec2 = boto3.client("ec2")

def lambda_handler(event, context):
    try:
        response_status = cfnresponse.SUCCESS
        r = {}

        if 'RequestType' in event and event['RequestType'] == 'Create':
            r["SubnetIds"] = get_subnet_ids(
                event['ResourceProperties']['SubnetCIDRBlocks'],
                event['ResourceProperties']['AvailabilityZones']
            )
            r["RouteTableIds"] = get_rt_ids(r["SubnetIds"])

        cfnresponse.send(event, context, response_status, r, '')

    except ClientError as exception:
        print(exception)
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physicalResourceId=event.get('PhysicalResourceId'), reason=str(exception))

def get_subnet_ids(cidr_blocks, azs):
    return [sn["SubnetId"] for sn in ec2.describe_subnets()["Subnets"]
            if sn["AvailabilityZone"] in azs and sn["CidrBlock"] in cidr_blocks]


def get_rt_ids(subnet_ids):
    return [r["RouteTableId"] for r in ec2.describe_route_tables(
        Filters=[
            {
                "Name":"association.subnet-id",
                "Values":subnet_ids
            }
        ]
    )["RouteTables"]]



    