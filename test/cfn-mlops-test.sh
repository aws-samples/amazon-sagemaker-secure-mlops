#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Package templates
S3_BUCKET_NAME=ilyiny-demo-cfn-artefacts-$AWS_DEFAULT_REGION
make package CFN_BUCKET_NAME=$S3_BUCKET_NAME

###############################################################
# MLOps project product portfolio for Service Catalog
STACK_NAME="sm-mlops-env-EnvironmentSCPortfolio-VX5MO02HEF0T"
PRINCIPAL_ROLE_ARN="arn:aws:iam::949335012047:role/service-role/sm-mlops-env-EnvironmentIAM-SageMakerExecutionRole-13FVOLBBPRXNC"
LAUNCH_ROLE_ARN="arn:aws:iam::949335012047:role/service-role/AmazonSageMakerServiceCatalogProductsLaunchRole"

aws cloudformation update-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/env-sc-portfolio.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --parameters \
        ParameterKey=EnvName,ParameterValue=sm-mlops \
        ParameterKey=EnvType,ParameterValue=dev \
        ParameterKey=SCMLOpsPortfolioPrincipalRoleArn,ParameterValue=$PRINCIPAL_ROLE_ARN \
        ParameterKey=SCMLOpsProductLaunchRoleArn,ParameterValue=$LAUNCH_ROLE_ARN


# Update SageMaker Service Catalog Project roles
STACK_NAME="sm-mlops-core-IAMSCSageMakerProjectRoles-136RA0IGCAFK7"

aws s3 cp build/$AWS_DEFAULT_REGION/core-iam-sc-sm-projects-roles.yaml s3://$S3_BUCKET_NAME/sagemaker-mlops/core-iam-sc-sm-projects-roles.yaml

aws cloudformation update-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/core-iam-sc-sm-projects-roles.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --capabilities CAPABILITY_NAMED_IAM
