#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#############################################################################################
# 1st level templates
# These templates do not contain any nested templates and can be directly deployed from the file
# no `aws cloudformation package` is needed

S3_BUCKET_NAME=ilyiny-cfn-artefacts-us-east-2
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
S3_BUCKET_NAME=ilyiny-cfn-artefacts-us-east-2
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

# IAM cross-account roles
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/env-iam-cross-account-deployment-role.yaml \
                --stack-name env-iam-cross-account-deployment-role \
                --capabilities CAPABILITY_NAMED_IAM \
                --parameter-overrides \
                EnvName=$ENV_NAME \
                EnvType=dev \
                PipelineExecutionRoleArn=arn:aws:iam::949335012047:role/service-role/AmazonSageMakerServiceCatalogProductsUseRole

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
        ParameterKey=DSAdmininstratorRole,ParameterValue=ds-team-us-east-2-DataScienceAdministrator \
        ParameterKey=DSAdministratorRoleArn,ParameterValue=arn:aws:iam::949335012047:role/ds-team-us-east-2-DataScienceAdministrator \
        ParameterKey=SecurityControlExecutionRoleArn,ParameterValue=arn:aws:iam::949335012047:role/ds-team-us-east-2-DSSageMakerDetectiveControlRole \
        ParameterKey=SCLaunchRoleArn,ParameterValue=arn:aws:iam::949335012047:role/ds-team-us-east-2-DSServiceCatalogLaunchRole

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
        ParameterKey=DSTeamAdministratorRoleName,ParameterValue=env-iam-roles-DataScienceTeamAdministratorRole-15CC4YYDTNY04 \
        ParameterKey=DataScientistRoleName,ParameterValue=env-iam-roles-DataScientistRole-PFIMUCN7IZ95 \
        ParameterKey=DSTeamAdministratorRoleArn,ParameterValue=arn:aws:iam::949335012047:role/env-iam-roles-DataScienceTeamAdministratorRole-15CC4YYDTNY04 \
        ParameterKey=DataScientistRoleArn,ParameterValue=arn:aws:iam::949335012047:role/env-iam-roles-DataScientistRole-PFIMUCN7IZ95  \
        ParameterKey=SageMakerExecutionRoleArn,ParameterValue=arn:aws:iam::949335012047:role/service-role/env-iam-roles-SageMakerExecutionRole-9CYD7UX2KG8D \
        ParameterKey=SetupLambdaExecutionRoleArn,ParameterValue=arn:aws:iam::949335012047:role/env-iam-roles-SetupLambdaExecutionRole-4G8FY4ULHFPN  \
        ParameterKey=SCProjectLaunchRoleArn,ParameterValue=arn:aws:iam::949335012047:role/env-iam-roles-SCProjectLaunchRole-1XKZQDT1TG067 \
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
aws cloudformation delete-stack --stack-name env-iam-cross-account-deployment-role
aws cloudformation delete-stack --stack-name env-iam-roles
aws cloudformation delete-stack --stack-name core-iam-shared-roles
aws cloudformation delete-stack --stack-name ds-team-vpc

# END of existing VPC and pre-provisioned IAM roles deployment 
#############################################################################################

#############################################################################################
# 2nd level-templates 
# These templates contain nested templates and need packaging via `aws cloudformation package`
# To deploy the 2nd level-templates we call `aws cloudformation create-stack`
#############################################################################################

# core-main.yaml
STACK_NAME="sagemaker-mlops-core"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/core-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME  \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=StackSetName,ParameterValue=$STACK_NAME


    # Parameter block if CreateIAMRoles = NO (the IAM role ARNs must be provided)
    ParameterKey=CreateIAMRoles,ParameterValue=NO
    ParameterKey=DSAdmininstrator,ParameterValue=
    ParameterKey=DSAdministratorRoleArn,ParameterValue=
    ParameterKey=SCLaunchRoleArn,ParameterValue=
    ParameterKey=SecurityControlExecutionRoleArn,ParameterValue=


# env-main.yaml
STACK_NAME="sagemaker-mlops-env"
ENV_NAME="sagemaker-mlops"
AVAILABILITY_ZONES=${AWS_DEFAULT_REGION}a

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/env-main.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev \
        ParameterKey=AvailabilityZones,ParameterValue=$AVAILABILITY_ZONES \
        ParameterKey=NumberOfAZs,ParameterValue=1
 
# data-science-environment-quickstart.yaml
STACK_NAME="ds-quickstart"
ENV_NAME="sagemaker-mlops"

aws cloudformation create-stack \
    --template-url https://s3.$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET_NAME/sagemaker-mlops/data-science-environment-quickstart.yaml \
    --region $AWS_DEFAULT_REGION \
    --stack-name $STACK_NAME \
    --disable-rollback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvName,ParameterValue=$ENV_NAME \
        ParameterKey=EnvType,ParameterValue=dev

###############################################################
# CI/CD test pipeline deployment


# Deploy IAM roles - same as we use for the solution stacks
aws cloudformation deploy \
                --template-file build/$AWS_DEFAULT_REGION/core-iam-shared-roles.yaml \
                --stack-name base-iam-shared-roles \
                --capabilities CAPABILITY_NAMED_IAM \
                --parameter-overrides \
                    DSAdministratorRoleName=base-$AWS_DEFAULT_REGION-DataScienceAdministrator \
                    SageMakerDetectiveControlExecutionRoleName=base-$AWS_DEFAULT_REGION-DSSageMakerDetectiveControlRole \
                    SCLaunchRoleName=base-$AWS_DEFAULT_REGION-DSServiceCatalogLaunchRole

aws s3 rb s3://codepipeline-sagemaker-secure-mlops-us-east-2 --force

aws cloudformation deploy \
                --template-file test/cfn_templates/test-pipeline.yaml \
                --stack-name sagemaker-mlops-pipeline-$AWS_DEFAULT_REGION \
                --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
                --parameter-overrides \
                CodeCommitRepositoryArn=arn:aws:codecommit:us-east-2:949335012047:sagemaker-secure-mlops \
                NotificationArn=arn:aws:sns:us-east-2:949335012047:ilyiny-demo-us-east-1-code-pipeline-sns \
                CodePipelineDeployRoleForDSEnvironmentArn=arn:aws:iam::949335012047:role/base-us-east-2-DSServiceCatalogLaunchRole


aws cloudformation delete-stack \
    --stack-name sagemaker-secure-mlops-automation-lambda-functions \
    --role-arn arn:aws:iam::949335012047:role/sagemaker-secure-mlops-codepipeline-deploy-role
             
