# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import json
import boto3
import cfnresponse
from botocore.exceptions import ClientError

sts = boto3.client("sts")
s3 = boto3.client("s3")
kms = boto3.client("kms")

def lambda_handler(event, context):
    try:
        response_status = cfnresponse.SUCCESS
        r = {}

        if 'RequestType' in event and event['RequestType'] == 'Create':
            r["Result"] = setup_cross_account_permissions(
                accounts=event['ResourceProperties']['Accounts'],
                principal_role_name=event['ResourceProperties']['PrincipalRoleName'],
                setup_role_name=event['ResourceProperties']['SetupRoleName'],
                bucket_name=event['ResourceProperties']['S3BucketName'],
                kms_key_id=event['ResourceProperties']['KMSKeyId'],
                s3_vpce_ssm_param_name=event['ResourceProperties']['S3VPCESSMParamName'],
                kms_vpce_ssm_pram_name=event['ResourceProperties']['KMSVPCESSMParamName'],
            )
            
        cfnresponse.send(event, context, response_status, r, '')

    except Exception as e:
        print(str(e))
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physicalResourceId=event.get('PhysicalResourceId'), reason=str(e))

def get_ssm_parameter(accounts, role, p_name):
    values = []
    for account_id in accounts:
        print(f"assume the role {role} in {account_id}")
        stsresponse = sts.assume_role(
            RoleArn=f"arn:aws:iam::{account_id}:role/{role}",
            RoleSessionName=f"newsession"
        )

        values.append(
            boto3.client("ssm",
                aws_access_key_id=stsresponse["Credentials"]["AccessKeyId"],
                aws_secret_access_key=stsresponse["Credentials"]["SecretAccessKey"],
                aws_session_token=stsresponse["Credentials"]["SessionToken"]
                ).get_parameter(Name=p_name)["Parameter"]["Value"]
        )

    print(f"values retrieved: {values}")
    return values

def append_list(value, list):
    if type(value) is str:
        return list + [value]
    else: 
        return list + value

def setup_policy(
    policy,
    principals,
    vpce_ids
):
    p = json.loads(policy)

    s = [s for s in p["Statement"] if s["Sid"] == "AllowCrossAccount"]
    v = [s for s in p["Statement"] if s["Sid"] == "DenyNoVPC"][0]

    s[0]["Principal"]["AWS"] = append_list(s[0]["Principal"]["AWS"], principals)
    v["Condition"]["StringNotEquals"]["aws:sourceVpce"] = append_list(v["Condition"]["StringNotEquals"]["aws:sourceVpce"], vpce_ids)

    print(f"policy:{p}")
    return json.dumps(p)

def setup_cross_account_permissions(
    accounts, 
    principal_role_name, 
    setup_role_name,
    bucket_name,
    kms_key_id,
    s3_vpce_ssm_param_name,
    kms_vpce_ssm_pram_name
):
    principals = [f"arn:aws:iam::{a}:role/{principal_role_name}" for a in accounts]

    # update S3 bucket policy
    s3.put_bucket_policy(
        Bucket=bucket_name, 
        Policy=setup_policy(
            policy=s3.get_bucket_policy(Bucket=bucket_name)["Policy"],
            principals=principals,
            vpce_ids=get_ssm_parameter(accounts, setup_role_name, s3_vpce_ssm_param_name)
        ))

    # update KMS key policy
    kms.put_key_policy(
        KeyId=kms_key_id, 
        PolicyName="default",
        Policy=setup_policy(
            policy=kms.get_key_policy(KeyId=kms_key_id,PolicyName="default")["Policy"],
            principals=principals,
            vpce_ids=get_ssm_parameter(accounts, setup_role_name, kms_vpce_ssm_pram_name)
        ))

    return "SUCCESS"