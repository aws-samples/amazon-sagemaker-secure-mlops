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

#############################################################################################
# Deployment into an existing VPC and with pre-provisioned IAM roles
#############################################################################################
S3_BUCKET_NAME=ilyiny-demo-cfn-artefacts-$AWS_DEFAULT_REGION
make package CFN_BUCKET_NAME=$S3_BUCKET_NAME

# stand-alone VPC deployment
STACK_NAME="ds-team-vpc"

aws cloudformation create-stack \
    --template-url https://aws-quickstart.s3.amazonaws.com/quickstart-aws-vpc/templates/aws-vpc.template.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=AvailabilityZones,ParameterValue=${AWS_DEFAULT_REGION}a\\,${AWS_DEFAULT_REGION}b\\,${AWS_DEFAULT_REGION}c  \
        ParameterKey=NumberOfAZs,ParameterValue=3

# SageMaker Service Catalog project roles
# run ONLY if AmazonSageMakerServiceCatalogProductsLaunchRole and AmazonSageMakerServiceCatalogProductsLaunchRole do NOT exist yet
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/core-iam-sc-sm-projects-roles.yaml \
                --stack-name core-iam-sc-sm-projects-roles \
                --capabilities CAPABILITY_NAMED_IAM 


# IAM shared roles
STACK_SET_NAME=ds-team
ENV_NAME=ds-team

aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/core-iam-shared-roles.yaml \
                --stack-name core-iam-shared-roles \
                --capabilities CAPABILITY_NAMED_IAM \
                --parameter-overrides \
                    DSAdministratorRoleName=$STACK_SET_NAME-$AWS_DEFAULT_REGION-DataScienceAdministrator \
                    SageMakerDetectiveControlExecutionRoleName=$STACK_SET_NAME-$AWS_DEFAULT_REGION-DSSageMakerDetectiveControlRole \
                    SCLaunchRoleName=$STACK_SET_NAME-$AWS_DEFAULT_REGION-DSServiceCatalogLaunchRole

# IAM DS environment roles
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-iam.yaml \
                --stack-name env-iam-roles \
                --capabilities CAPABILITY_NAMED_IAM \
                --parameter-overrides \
                EnvName=$ENV_NAME \
                EnvType=dev

# IAM model deployment roles - must be deployed in each dev, stating, production AWS accounts
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-iam-target-account-roles.yaml \
                --stack-name env-iam-target-account-roles \
                --capabilities CAPABILITY_NAMED_IAM \
                --parameter-overrides \
                EnvName=$ENV_NAME \
                EnvType=dev \
                PipelineExecutionRoleArn=arn:aws:iam::ACCOUNT_ID:role/service-role/AmazonSageMakerServiceCatalogProductsUseRole

# Get IAM role ARNs
aws cloudformation describe-stacks \
    --stack-name core-iam-shared-roles  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

# core infrastructure
STACK_NAME="ds-team-core"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/core-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME  \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=StackSetName,ParameterValue=$STACK_NAME \
        ParameterKey=CreateIAMRoles,ParameterValue=NO \
        ParameterKey=DSAdministratorRoleArn,ParameterValue=arn:aws:iam::ACCOUNT_ID:role/ds-team-us-east-2-DataScienceAdministrator \
        ParameterKey=SecurityControlExecutionRoleArn,ParameterValue=arn:aws:iam::ACCOUNT_ID:role/ds-team-us-east-2-DSSageMakerDetectiveControlRole \
        ParameterKey=SCLaunchRoleArn,ParameterValue=arn:aws:iam::ACCOUNT_ID:role/ds-team-us-east-2-DSServiceCatalogLaunchRole

# show the assume DSAdministrator role link
aws cloudformation describe-stacks \
    --stack-name ds-team-core  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

# show shared IAM roles
aws cloudformation describe-stacks \
    --stack-name env-iam-roles  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

# show VPC info
aws cloudformation describe-stacks \
    --stack-name ds-team-vpc  \
    --output table \
    --query "Stacks[0].Outputs[*].[OutputKey, OutputValue]"

# data science environment
STACK_NAME="ds-team-env"
ENV_NAME="ds-team-env"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/env-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev \
        ParameterKey=CreateEnvironmentIAMRoles,ParameterValue=NO \
        ParameterKey=CreateS3VPCEndpoint,ParameterValue=NO \
        ParameterKey=DSTeamAdministratorRoleArn,ParameterValue=arn:aws:iam::ACCOUNT_ID:role/env-iam-roles-DataScienceTeamAdministratorRole-15CC4YYDTNY04 \
        ParameterKey=DataScientistRoleArn,ParameterValue=arn:aws:iam::ACCOUNT_ID:role/env-iam-roles-DataScientistRole-PFIMUCN7IZ95  \
        ParameterKey=SageMakerExecutionRoleArn,ParameterValue=arn:aws:iam::ACCOUNT_ID:role/service-role/env-iam-roles-SageMakerExecutionRole-9CYD7UX2KG8D \
        ParameterKey=SetupLambdaExecutionRoleArn,ParameterValue=arn:aws:iam::ACCOUNT_ID:role/env-iam-roles-SetupLambdaExecutionRole-4G8FY4ULHFPN  \
        ParameterKey=SCProjectLaunchRoleArn,ParameterValue=arn:aws:iam::ACCOUNT_ID:role/env-iam-roles-SCProjectLaunchRole-1XKZQDT1TG067 \
        ParameterKey=CreateVPC,ParameterValue=NO \
        ParameterKey=CreateNATGateways,ParameterValue=NO \
        ParameterKey=ExistingVPCId,ParameterValue=vpc-0b1a38a31305c97d1 \
        ParameterKey=ExistingS3VPCEndpointId,ParameterValue=vpce-05799d9d4fd694936 \
        ParameterKey=CreatePrivateSubnets,ParameterValue=NO \
        ParameterKey=PrivateSubnet1ACIDR,ParameterValue=10.0.0.0/19 \
        ParameterKey=PrivateSubnet2ACIDR,ParameterValue=10.0.32.0/19 \
        ParameterKey=PrivateSubnet3ACIDR,ParameterValue=10.0.64.0/19  \
        ParameterKey=CreateVPCFlowLogsToCloudWatch,ParameterValue=NO \
        ParameterKey=CreateVPCFlowLogsRole,ParameterValue=NO \
        ParameterKey=AvailabilityZones,ParameterValue=${AWS_DEFAULT_REGION}a\\,${AWS_DEFAULT_REGION}b\\,${AWS_DEFAULT_REGION}c \
        ParameterKey=NumberOfAZs,ParameterValue=3

# Clean up
aws cloudformation delete-stack --stack-name ds-team-env
aws cloudformation delete-stack --stack-name ds-team-core
aws cloudformation delete-stack --stack-name env-iam-target-account-roles
aws cloudformation delete-stack --stack-name env-iam-roles
aws cloudformation delete-stack --stack-name core-iam-shared-roles
aws cloudformation delete-stack --stack-name ds-team-vpc

# END of existing VPC and pre-provisioned IAM roles deployment 
#############################################################################################
 
# data-science-environment-quickstart.yaml
STACK_NAME="ds-quickstart"
ENV_NAME="sm-mlops"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/data-science-environment-quickstart.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev





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

SM_PROJECT_NAME="test11-deploy"
SM_PROJECT_ID="p-6dyr0oam0c9s"
MODEL_PACKAGE_NAME="arn:aws:sagemaker:us-east-1:340327315379:model-package/test11-deploy-p-6dyr0oam0c9s/2"
EXECUTION_ROLE_NAME="sm-mlops-env-EnvironmentT-SageMakerModelExecutionR-DTXUGN38COKK"
SM_SUBNET_ID="sm-mlops-staging-private-subnet-ids"
SM_SG_ID="sm-mlops-staging-sagemaker-sg-ids"
ENV_NAME="sm-mlops"
ENV_TYPE="staging"
EBS_KMS_KEY_ID="arn:aws:kms:us-east-1:340327315379:key/9eca9a44-9b46-42c8-88af-474124ec9d34"
S3_KMS_KEY_ID="arn:aws:kms:us-east-1:340327315379:key/a8e3e301-3fea-4784-bd6f-5b5aea3ca384"
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
