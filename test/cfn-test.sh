#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#############################################################################################
# 1st level templates
# These templates do not contain any nested templates and can be directly deployed from the file
# no `aws cloudformation package` is needed

S3_BUCKET_NAME=

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


# IAM Shared roles
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/core-iam-shared-roles.yaml \
                --stack-name core-iam-shared-roles \
                --capabilities CAPABILITY_NAMED_IAM \
                --parameter-overrides \
                StackSetName=sagemaker-mlops \
                CreateIAMUserRoles=NO

# IAM DS environment roles
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-iam.yaml \
                --stack-name env-iam-roles \
                --capabilities CAPABILITY_NAMED_IAM \
                --parameter-overrides \
                EnvName=sagemaker-mlops \
                EnvType=dev \
                CreateIAMUserRoles=NO

# SageMaker Studio
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-sagemaker-studio.yaml \
                --stack-name sagemaker-mlops-sagemaker-studio \
                --parameter-overrides \
                EnvName=sagemaker-mlops \
                EnvType=dev \
                VPCId=vpc-0c09b9d75c41a8661\
                SageMakerStudioSubnetIds=subnet-0b9a35afb800fa51c,subnet-0aaa78c2744978657 \
                SageMakerSecurityGroupIds=sg-0ee201d5bbfe32ed6 \
                SageMakerExecutionRoleArn=arn:aws:iam::949335012047:role/service-role/sagemaker-mlops-dev-sagemaker-execution-role \
                SetupLambdaExecutionRoleArn=arn:aws:iam::949335012047:role/sagemaker-mlops-dev-setup-lambda-execution-role \
                SageMakerStudioStorageKMSKeyId=38b45ed2-05a7-4d35-8246-c16252c0ed19

# arn:aws:kms:eu-central-1:949335012047:key/49cf6b9a-08bb-452f-b50d-6b4dac42cca1 


#############################################################################################
# 2nd level-templates 
# These templates contain nested templates and need packaging via `aws cloudformation package`
# To deploy the 2nd level-templates we call `aws cloudformation create-stack`

# core-main.yaml
STACK_NAME="sagemaker-mlops-core"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/core-main.yaml \
    --region eu-central-1 \
    --stack-name $STACK_NAME  \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=StackSetName,ParameterValue="mlops-core-$AWS_DEFAULT_REGION" 

# env-main.yaml
STACK_NAME="sagemaker-mlops-env"
ENV_NAME="sagemaker-mlops"
AVAILABILITY_ZONES="eu-central-1a\\,eu-central-1b"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/env-main.yaml \
    --region eu-central-1 \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev \
        ParameterKey=CreateSageMakerStudioDomain,ParameterValue=NO \
        ParameterKey=AvailabilityZones,ParameterValue=$AVAILABILITY_ZONES \
        ParameterKey=NumberOfAZs,ParameterValue=2 \
        ParameterKey=CreateNATGateways,ParameterValue="NO"
 
# data-science-environment-quickstart.yaml
STACK_NAME="ds-quickstart"
ENV_NAME="sagemaker-mlops"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/data-science-environment-quickstart.yaml \
    --region eu-central-1 \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev