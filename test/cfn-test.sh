#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#############################################################################################
# 1st level templates
# These templates do not contain any nested templates and can be directly deployed from the file
# no `aws cloudformation package` is needed

S3_BUCKET_NAME=ilyiny-demo-cfn-artefacts-$AWS_DEFAULT_REGION
make package CFN_BUCKET_NAME=$S3_BUCKET_NAME

# env-vpc.yaml
# New VPC + private subnets only
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-vpc-eu-central-1.yaml \
                --stack-name sagemaker-mlops-env-vpc \
                --parameter-overrides \
                EnvName=sagemaker-mlops \
                EnvType=dev \
                AvailabilityZones=eu-central-1a,eu-central-1b,eu-central-1c \
                NumberOfAZs=3 \
                CreateNATGateways=NO \

# Assertion error: NAT Gateways = YES but Private Subnets = NO
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-vpc-eu-central-1.yaml \
                --stack-name sagemaker-mlops-env-vpc \
                --parameter-overrides \
                EnvName=sagemaker-mlops \
                EnvType=dev \
                AvailabilityZones=eu-central-1a,eu-central-1b,eu-central-1c \
                NumberOfAZs=3 \
                CreateNATGateways=YES \
                CreatePrivateSubnets=NO \

# New VPC + NAT Gateways
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-vpc-eu-central-1.yaml \
                --stack-name sagemaker-mlops-env-vpc \
                --parameter-overrides \
                EnvName=sagemaker-mlops \
                EnvType=dev \
                AvailabilityZones=eu-central-1a,eu-central-1b,eu-central-1c \
                NumberOfAZs=3 \
                CreateNATGateways=YES \

# Existing VPC + private subnets only
# 172.31.0.0/16
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-vpc-eu-central-1.yaml \
                --stack-name sagemaker-mlops-env-vpc \
                --parameter-overrides \
                EnvName=sagemaker-mlops \
                EnvType=dev \
                AvailabilityZones=eu-central-1a,eu-central-1b,eu-central-1c \
                NumberOfAZs=3 \
                CreateNATGateways=NO \
                ExistingVPCId=vpc-d5dc5ebf \
                PrivateSubnet1ACIDR=172.31.48.0/20\
                PrivateSubnet2ACIDR=172.31.64.0/20 \
                PrivateSubnet3ACIDR=172.31.80.0/20 \

# Existing VPC + NAT Gateways
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-vpc-eu-central-1.yaml \
                --stack-name sagemaker-mlops-env-vpc \
                --parameter-overrides \
                EnvName=sagemaker-mlops \
                EnvType=dev \
                AvailabilityZones=eu-central-1a,eu-central-1b,eu-central-1c \
                NumberOfAZs=3 \
                CreateNATGateways=YES \
                ExistingVPCId=vpc-d5dc5ebf \
                PrivateSubnet1ACIDR=172.31.48.0/20\
                PrivateSubnet2ACIDR=172.31.64.0/20 \
                PrivateSubnet3ACIDR=172.31.80.0/20 \
                PublicSubnet1CIDR=172.31.96.0/20 \
                PublicSubnet2CIDR=172.31.112.0/20 \
                PublicSubnet3CIDR=172.31.128.0/20 \

# SageMaker Studio
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-sagemaker-studio.yaml \
                --stack-name sagemaker-mlops-sagemaker-studio \
                --role-arn  \
                --parameter-overrides \
                EnvName=sagemaker-mlops \
                EnvType=dev \
                VPCId= \
                SageMakerStudioSubnetIds= \
                SageMakerSecurityGroupIds= \
                SageMakerStudioStorageKMSKeyId= \
                SageMakerExecutionRoleArn= \
                SetupLambdaExecutionRoleArn=

# Env-KMS
aws cloudformation deploy \
    --template-file build/$AWS_DEFAULT_REGION/env-kms.yaml \
    --stack-name env-kms-test \
    --parameter-overrides \
        EnvName=sagemaker-mlops \
        EnvType=dev \
        DSTeamAdministratorRoleArn= \
        DataScientistRoleArn= \
        SageMakerExecutionRoleArn= \
        SCLaunchRoleArn=  \
        VPCEndpointS3Id= 

# data-science-environment-quickstart.yaml
STACK_NAME="ds-quickstart"
ENV_NAME="sm-mlops"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/data-science-environment-quickstart.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev \
        ParameterKey=SeedCodeS3BucketName,ParameterValue=$S3_BUCKET_NAME

# Update SageMaker Service Catalog Project roles
STACK_NAME="sm-mlops-core-IAMSCSageMakerProjectRoles-136RA0IGCAFK7"

aws s3 cp build/$AWS_DEFAULT_REGION/core-iam-sc-sm-projects-roles.yaml s3://$S3_BUCKET_NAME/sagemaker-mlops/core-iam-sc-sm-projects-roles.yaml

aws cloudformation update-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/core-iam-sc-sm-projects-roles.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --capabilities CAPABILITY_NAMED_IAM

# ################################################################################
# SageMaker endpoint deployment
# ################################################################################

AWS_MODEL_ACCOUNT_ID = "account id where model artifact stored"
SM_PROJECT_NAME="test11-deploy"
SM_PROJECT_ID="p-6dyr0oam0c9s"
MODEL_PACKAGE_NAME="arn:aws:sagemaker:us-east-1:$AWS_MODEL_ACCOUNT_ID:model-package/test11-deploy-p-6dyr0oam0c9s/2"
EXECUTION_ROLE_NAME="sm-mlops-env-EnvironmentT-SageMakerModelExecutionR-DTXUGN38COKK"
SM_SUBNET_ID="sm-mlops-staging-private-subnet-ids"
SM_SG_ID="sm-mlops-staging-sagemaker-sg-ids"
ENV_NAME="sm-mlops"
ENV_TYPE="staging"
EBS_KMS_KEY_ID="arn:aws:kms:us-east-1:$AWS_MODEL_ACCOUNT_ID:key/9eca9a44-9b46-42c8-88af-474124ec9d34"
S3_KMS_KEY_ID="arn:aws:kms:us-east-1:$AWS_MODEL_ACCOUNT_ID:key/a8e3e301-3fea-4784-bd6f-5b5aea3ca384"
OU_ID="ou-fi18-56v340tb"

aws cloudformation deploy \
    --template-file build/cfn-sm-endpoint-template.yaml \
    --stack-name $ENV_NAME-$ENV_TYPE-sm-endpoint \
    --parameter-overrides \
    SageMakerProjectName=$SM_PROJECT_NAME \
    SageMakerProjectId=$SM_PROJECT_ID \
    ModelPackageName=$MODEL_PACKAGE_NAME \
    EndpointInstanceCount=1 \
    EndpointInstanceType=ml.t2.medium \
    ExecutionRoleName=$EXECUTION_ROLE_NAME \
    EnvName=$ENV_NAME \
    EnvType=$ENV_TYPE \
    SageMakerSubnetIds=$SM_SUBNET_ID \
    SageMakerSecurityGroupIds=$SM_SG_ID \
    VolumeKmsKeyArn=$EBS_KMS_KEY_ID \
    OrgUnitId=$OU_ID


aws cloudformation deploy \
    --template-file build/$AWS_DEFAULT_REGION/env-s3.yaml \
    --stack-name env-s3-test \
    --parameter-overrides \
        EnvName=$ENV_NAME \
        EnvType=$ENV_TYPE \
        DataBucketName=$ENV_NAME-$ENV_TYPE-$AWS_DEFAULT_REGION-$AWS_MODEL_ACCOUNT_ID-data \
        ModelBucketName=$ENV_NAME-$ENV_TYPE-$AWS_DEFAULT_REGION-$AWS_MODEL_ACCOUNT_ID-models \
        VPCEndpointS3Id="xxxx" 
