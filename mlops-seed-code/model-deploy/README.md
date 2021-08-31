# Secure MLOps for SageMaker

This is a sample code repository for demonstrating how you can organize your code for deploying an realtime inference Endpoint infrastructure in multi-account environment. This code repository is created as part of creating a Project in SageMaker. 

This code repository has the code to find the latest approved ModelPackage for the associated ModelPackageGroup and automatically deploy it to the Endpoint on detecting a change (`build.py`). This code repository also defines the CloudFormation template which defines the Endpoints as infrastructure. It also has configuration files associated with `staging` and `production` stages. 

This CI/CD pipeline is triggered by each commit to this repository and by any state change (e.g. registering a new model) in the SageMaker Model Package.
Upon triggering a deployment:
1. the CodePipeline pipeline will build the artifacts (configuration and deployment CloudFormation template). 
2. After the build step, the CodePipeline will deploy the first endpoint - `staging` into the **staging accounts** which were defined during the data science provisioning process by `OrganizationalUnitStagingId` or `StagingAccountList` parameters. 
3. After staging deployment is completed, the CodePipeline runs the TestStaging step and waits for a **manual approval step** for promotion to the prod stage. You will need to go to CodePipeline AWS Managed Console to complete this step.
4. After manual approval the CodePipeline will deploy the second endpoint - `production` into the **production accounts** defined by `OrganizationalUnitProdId` or `ProductionAccountList` parameters.

❗ This MLOps project uses the values from `OrganizationalUnitStagingId`/`OrganizationalUnitProdId` or `StagingAccountList`/`ProductionAccountList` parameters provided at data science stack deployment time. 

The following diagram shows this CI/CD Model Deployment pipeline in the context of the whole MLOps Data Science solution.

![CI/CD model deployment](img/ml-ops-architecture-model-deploy.png)

You own this seed code and you can modify this template to reflect your environment, MLOps guidelines, and project governance. You can also add additional tests for your custom validation to the TestStaging step.

A description of some of the artifacts is provided below.

## Organization of the SageMaker model deploy seed code
`buildspec.yml`
 - this file is used by the CodePipeline's Build stage to package a CloudFormation template for `cfn-sm-endpoint-template.yml`.

`build.py`
 - this python file contains code to get the latest approve package arn and exports staging and configuration files.

`cfn-sm-endpoint-template.yml`
 - this CloudFormation file is packaged by the build step into a CloudFormation template file and is deployed to `staging` and `production` stages.

`staging-config-template.json`
 - this configuration files is used to customize staging stage in the pipeline.

`prod-config-template.json`
 - this configuration files is used to customize production stage in the pipeline.

`test\buildspec.yml`
  - this file is used by the CodePipeline's DeployStaging stage to run the test code of the following python file

`test\test.py`
  - this python file contains code to describe and invoke the staging endpoint.
  - **Add your custom endpoint test logic to this file**

## Multi-account model deployment
This MLOps project supports multi-account model deployment. An approved version of the model package is deployed via an [CodePipeline](https://aws.amazon.com/codepipeline/) CI/CD pipeline into the staging and production accounts.

If you provided the values for `OrganizationalUnitStagingId`/`OrganizationalUnitProdId` or `StagingAccountList`/`ProductionAccountList` parameters during the data science environment deployment and set the parameter `MultiAccountDeployment` to `YES` for the MLOps project deployment, the model will be deployed to the staging and production accounts. Otherwise the model will be deployed into the same data science account with the development environment and this MLOps project.


### AWS Organizations setup for MLOps model deploy
You can use AWS Organizations OUs to define which accounts belong to the staging and production units.
The model will be deployed to all accounts in each of the staging and production OUs.

For example, your Organizations structure can look like the following:
+ Root
    - multi-account-deployment (OU)
        * `111111111111` (data science development account with SageMaker Studio)
        * staging (OU)
            * `222222222222` (data science staging AWS account)
            * `333333333333` (data science staging AWS account)
        * production (OU)
            * `444444444444` (data science production AWS account)

In this case, the model will be deployed to `222222222222` and `333333333333` in the staging OU and to the `444444444444` in the production OU.

Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
SPDX-License-Identifier: MIT-0