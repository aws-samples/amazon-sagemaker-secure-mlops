#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

###############################################################
# CI/CD test pipeline deployment
# Package templates
S3_BUCKET_NAME=ilyiny-demo-cfn-artefacts-$AWS_DEFAULT_REGION
make package CFN_BUCKET_NAME=$S3_BUCKET_NAME
ACCOUNT_ID=949335012047

# one-off Amazon S3 bucket creation
PROJECT_NAME=sm-mlops
aws s3 mb s3://codepipeline-${PROJECT_NAME}-$AWS_DEFAULT_REGION --region $AWS_DEFAULT_REGION
aws s3 mb s3://codepipeline-${PROJECT_NAME}-eu-central-1 --region eu-central-1
aws s3 mb s3://codepipeline-${PROJECT_NAME}-eu-west-1 --region eu-west-1
aws s3 mb s3://codepipeline-${PROJECT_NAME}-eu-west-2 --region eu-west-2

# Deploy a new CI/CD stack
S3_BUCKET_NAME=ilyiny-demo-cfn-artefacts-$AWS_DEFAULT_REGION
REPOSITORY_ARN=arn:aws:codecommit:$AWS_DEFAULT_REGION:${ACCOUNT_ID}:sagemaker-secure-mlops
SNS_NOTIFICATION_ARN=arn:aws:sns:$AWS_DEFAULT_REGION:${ACCOUNT_ID}:ilyiny-demo-us-east-1-code-pipeline-sns
aws cloudformation deploy \
                --template-file test/cfn_templates/create-base-infra-pipeline.yaml \
                --stack-name base-infra-$AWS_DEFAULT_REGION \
                --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
                --s3-bucket $S3_BUCKET_NAME \
                --parameter-overrides \
                CodeCommitRepositoryArn=$REPOSITORY_ARN \
                NotificationArn=$SNS_NOTIFICATION_ARN

# Clean up
# Delete stack under a role other than it has been created
STACK_NAME=
aws cloudformation delete-stack \
    --stack-name $STACK_NAME \
    --role-arn arn:aws:iam::ACCOUNT_ID:role/sagemaker-secure-mlops-codepipeline-deploy-role
             
aws cloudformation delete-stack --stack-name base-env-iam-target-account-roles
aws cloudformation delete-stack --stack-name base-core-iam-shared-roles
aws cloudformation delete-stack --stack-name base-env-iam-roles
aws cloudformation delete-stack --stack-name sm-mlops-$AWS_DEFAULT_REGION-VPC-pipeline
aws cloudformation delete-stack --stack-name base-vpc 

aws cloudformation delete-stack --stack-name base-infra-$AWS_DEFAULT_REGION

PROJECT_NAME=sm-mlops
aws s3 rb s3://codepipeline-${PROJECT_NAME}-$AWS_DEFAULT_REGION --force
aws s3 rb s3://codepipeline-${PROJECT_NAME}-eu-central-1 --force
aws s3 rb s3://codepipeline-${PROJECT_NAME}-eu-west-1 --force
aws s3 rb s3://codepipeline-${PROJECT_NAME}-eu-west-2 --force

# update pipeline stack
aws s3 cp test/cfn_templates/create-base-infra-pipeline.yaml s3://$S3_BUCKET_NAME/sagemaker-mlops/create-base-infra-pipeline.yaml

aws cloudformation update-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/create-base-infra-pipeline.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name base-infra-$AWS_DEFAULT_REGION \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=CodeCommitRepositoryArn,ParameterValue=arn:aws:codecommit:$AWS_DEFAULT_REGION:ACCOUNT_ID:sagemaker-secure-mlops \
        ParameterKey=NotificationArn,ParameterValue=arn:aws:sns:$AWS_DEFAULT_REGION:ACCOUNT_ID:ilyiny-demo-us-east-1-code-pipeline-sns
