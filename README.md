# Amazon SageMaker secure MLOps
The goal of the solution is to demonstrate a deployment of Amazon SageMaker Studio into a secure controlled environment with multi-layer security and implementation of secure MLOps CI/CD pipelines. The solution also implements a multi-account model deployment pipeline.

This GitHub repository is for the two-part series of blog posts on [AWS Machine Learning Blog](https://aws.amazon.com/blogs/machine-learning/):
- [Secure multi-account model deployment with Amazon SageMaker: Part 1](https://aws.amazon.com/blogs/machine-learning/part-1-secure-multi-account-model-deployment-with-amazon-sagemaker/)
- [Secure multi-account model deployment with Amazon SageMaker: Part 2](https://aws.amazon.com/blogs/machine-learning/part-2-secure-multi-account-model-deployment-with-amazon-sagemaker/)

This solution covers the main four topics:
1. Secure deployment of [Amazon SageMaker Studio](https://aws.amazon.com/sagemaker/studio/) into a new or an existing secure environment (VPC, private subnets, VPC endpoints, security groups). We implement end-to-end data encryption and fine-grained access control
2. Self-service data science environment provisioning based on [AWS Service Catalog](https://aws.amazon.com/servicecatalog/?aws-service-catalog.sort-by=item.additionalFields.createdDate&aws-service-catalog.sort-order=desc) and [AWS CloudFormation](https://aws.amazon.com/cloudformation/)
3. Self-service provisioning of [MLOps project templates](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-projects-templates.html) in Studio
4. MLOps CI/CD automation using [SageMaker projects](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-projects-whatis.html) and [SageMaker Pipelines](https://docs.aws.amazon.com/sagemaker/latest/dg/pipelines.html) for model training and multi-account deployment

## Content
- [Solution architecture](#solution-architecture)
- [Multi-account configuration](#multi-account-configuration)
- [Role configuration](#role-configuration)
- [IAM configuration](#iam-configuration)
- [Multi-account model deployment](#multi-account-model-deployment)
- [Security](#security)
- [MLOps](#mlops)
- [Deployment guide](#deployment)
- [Clean up](#clean-up)
- [Resources](#resources)
- [Appendixes](#appendixes)

## Solution architecture
This section describes the overall solution architecture.

### Overview
![Solution overview](design/ml-ops-solution-overview.drawio.svg)

**1 – AWS Service Catalog**  
The end-to-end deployment of the data science environment is delivered as an [AWS Service Catalog](https://aws.amazon.com/servicecatalog) self-provisioned product. One of the main advantages of using AWS Service Catalog for self- provisioning is that authorized users can configure and deploy available products and AWS resources on their own without needing full privileges or access to AWS services. The deployment of all AWS Service Catalog products happens under a specified service role with the defined set of permissions, which are unrelated to the user’s permissions.

**2 – Amazon SageMaker Studio Domain**  
The data science Environment product in the AWS Service Catalog creates an [Amazon SageMaker Studio domain](https://docs.aws.amazon.com/sagemaker/latest/dg/gs-studio-onboard.html), which consists of a list of authorized users, configuration settings, and an Amazon Elastic File System ([Amazon EFS](https://aws.amazon.com/efs/)) volume, which contains data for the users, including notebooks, resources, and artifacts.

**3,4 – SageMaker MLOps project templates**  
The solution delivers the customized versions of [SageMaker MLOps project templates](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-projects-whatis.html). Each MLOps template provides an automated model building and deployment pipeline using continuous integration and continuous delivery (CI/CD). The delivered templates are configured for the secure multi-account model deployment and are fully integrated in the provisioned data science environment. The project templates are provisioned in the Studio via AWS Service Catalog.

**5,6 – CI/CD workflows**  
The MLOps projects implement CI/CD using SageMaker Pipelines and [AWS CodePipeline](https://aws.amazon.com/codepipeline/), [AWS CodeCommit](https://aws.amazon.com/codecommit/), and [AWS CodeBuild](https://aws.amazon.com/codebuild/). SageMaker Pipelines are responsible for orchestrating workflows across each step of the ML process and task automation including data loading, data transformation, training, tuning and validation, and deployment. Each model is tracked via the [SageMaker model registry](https://docs.aws.amazon.com/sagemaker/latest/dg/model-registry.html), which stores the model metadata, such as training and validation metrics and data lineage, manages model versions and the approval status of the model.
This solution supports secure multi-account model deployment using [AWS Organizations](https://aws.amazon.com/organizations/) or via simple target account lists.

**7 – Secure infrastructure**  
Studio domain is deployed in a dedicated VPC. Each [elastic network interface (ENI)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html) used by SageMaker domain or workload is created within a private dedicated subnet and attached to the specified security groups. The data science environment VPC can be configured with internet access via an optional [NAT gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html). You can also run this VPC in internet-free mode without any inbound or outbound internet access. 
All access to the AWS public services is routed via [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/endpoint-services-overview.html). Traffic between your VPC and the AWS services does not leave the Amazon network and is not exposed to the public internet.

**8 – Data security**  
All data in the data science environment, which is stored in [Amazon S3 buckets](https://aws.amazon.com/s3/), [Amazon EBS](https://aws.amazon.com/ebs) and EFS volumes, is encrypted at rest using [customer-managed AWK Key Management Service (KMS) keys](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#customer-cmk). All data transfer between platform components, API calls, and inter-container communication is protected using Transport Layer Security (TLS 1.2) protocol. 
Data access from the SageMaker Studio notebooks or any SageMaker workload to the environment Amazon S3 buckets is governed by the combination of the [Amazon S3 bucket and user policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-iam-policies.html) and [S3 VPC endpoint policy](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html#vpc-endpoint-policies).

## AWS account, team, and project configuration
The following diagram shows the implemented team and AWS account structure for the solution:

![Team structure](design/ml-ops-team-structure.drawio.svg)

The data science environment has a three-level organizational structure: Enterprise (Organizational Unit), Team (Environment), and Project.

+ **Enterprise** level: The highest level in hierarchy, represented by the `DS Administrator` role and _data science portfolio_ in AWS Service Catalog. A data science environment per team is provisioned via the AWS Service Catalog self-service into a dedicated data science AWS Account.
+ **Team/Environment** level: There is one dedicated data science Team AWS account and one Studio domain per region per AWS account. `DS Team Administrator `can create user profiles in Studio for different user roles with different permissions, and also provision a CI/CD MLOps pipelines per project. The DS Administrator role is responsible for approving ML models and deployment into staging and production accounts. Based on role permission setup you can implement fine-granular separation of rights and duties per project. You can find more details on permission control with IAM policies and resource tagging in the blog post [Configuring Amazon SageMaker Studio for teams and groups with complete resource isolation](https://aws.amazon.com/fr/blogs/machine-learning/configuring-amazon-sagemaker-studio-for-teams-and-groups-with-complete-resource-isolation/) on [AWS Machine Learning Blog](https://aws.amazon.com/blogs/machine-learning/)
+ **Project** level: This is the individual project level and represented by CI/CD pipelines which are provisioned via SageMaker projects in Studio

The recently published AWS whitepaper [Build a Secure Enterprise Machine Learning Platform on AWS](https://docs.aws.amazon.com/whitepapers/latest/build-secure-enterprise-ml-platform/build-secure-enterprise-ml-platform.html) gives detailed overview and outlines the recommended practices for more generic use case of building multi-account enterprise-level data science environments.

This is a proposed environment structure and can be adapted for your specific requirements, organizational and governance structure, and project methodology.

## Multi-account configuration
The best practice for implementing production and real-world data science environment is to use multiple AWS accounts. The multi-account approaches has the following benefits:
- Supports multiple unrelated teams
- Ensures fine-grained security and compliance controls
- Minimizes the blast radius
- Provides workload and data isolation
- Facilitates the billing and improves cost visibility and control
- Separates between development, test, and production 

You can find a recommended multi-account recommended practices in the whitepaper [Build a Secure Enterprise Machine Learning Platform on AWS](https://docs.aws.amazon.com/whitepapers/latest/build-secure-enterprise-ml-platform/aws-accounts.html).

The solution implements the following multi-account approach:
+ A dedicated AWS account (development account) per data science team and one Amazon SageMaker Studio domain per region per account
+ Dedicated AWS accounts for staging and production of AI/ML models
+ Optional usage of AWS Organizations to enable trust and security control policies for member AWS accounts

Without loss of generality, this solution uses three account groups: 
+ **Development** (data science) main account: this account is used by data scientists and ML engineers to perform experimentation and development. Data science tools such as Studio is used in the development account. Amazon S3 buckets with data and models, code repositories and CI/CD pipelines are hosted in this account. Models are built, trained, validated, and registered in the model repository in this account. 
+ **Testing/staging/UAT** accounts: Validated and approved models are first deployed to the staging account, where the automated unit and integration tests are run. Data scientists and ML engineers do have read-only access to this account.
+ **Production** accounts: Tested models from the staging accounts are finally deployed to the production account for both online and batch inference.

❗ For real-world production setup we recommend to use additional two account groups:
+ **Shared services** accounts: This account hosts common resources like team code repositories, CI/CD pipelines for MLOps workflows, Docker image repositories, service catalog portfolios, model registries, and library package repositories. 
+ **Data management** accounts: A dedicated AWS account to store and manage all data for the machine learning process. It is recommended to implement strong data security and governance practices using [AWS Data Lake](https://aws.amazon.com/solutions/implementations/data-lake-solution/) and [AWS Lake Formation](https://aws.amazon.com/lake-formation/).

Each of these account groups can have multiple AWS accounts and environments for development and testing of services and storing different type of data.

## Role configuration
Initial baselines for the IAM roles are taken from [Secure data science reference architecture](https://github.com/aws-samples/secure-data-science-reference-architecture) open source project on GitHub. You can adjust role permission policies based on your specific security guidelines and requirements.

This solution uses the concept of following roles in Model Development Life Cycle (MDLC):  

+ **Data scientist**:  
  “Project user” role for a DataScientist. This solution implements a wide permission baseline. You might trim the permissions down for your real-world projects to reflect your security environment and requirements. The provisioned role uses the AWS managed permission policy for the job function `DataScientist`:  
    - Model training and evaluation in SageMaker, Studio, Notebooks, SageMaker JumpStart
    - Feature engineering
    - Starting ML pipelines
    - Deploy models to the model registry
    - GitLab permissions

    Permission baseline:
    - AWS managed policy `DataScientist`
    - Data locations (S3): only a defined set of S3 buckets (e.g. Data and Model)
    - SageMaker, Studio, Notebooks

    Role definition: [CloudFormation](../cfn_templates/env-iam.yaml)

+ **Data science team administrator**:  
   This is the admin role for a team or data science environment. In real-world setup you might want to add one more level of hierarchy and add an administrator role per project (or group of projects) – it creates a separation of duties between projects and minimize the blast radius. In this solution we are going to have one administrator role per team or "environment", effectively meaning that Project Administrator = Team Administrator. The main responsibilities of the role are:  
    - ML infrastructure management and operations (endpoints, monitoring, scaling, reliability/high availability, BCM/DR)
    - Model hosting
    - Production integration
    - Model approval for deployment in staging and production
    - Project template (MLOps) provisioning
    - Provision products via AWS Service Catalog
    - GitLab repository access

    Permission baseline:
    - PROD account
    - ML infrastructure
    - Data locations (S3)

    Role definition: [CloudFormation](../cfn_templates/env-iam.yaml)

+ **Data science administrator**:  
  This is overarching admin role for the data science projects and setting up the secure SageMaker environment. It uses AWS managed policies only. This role has the following responsibilities:
    - Provisioning of the shared data science infrastructure
    - Model approval for production
    - Deploys data science environments via the AWS Service Catalog

    Permission baseline:
    - Approvals (MLOps, Model registry, CodePipeline)
    - Permissions to deploy products from AWS Service Catalog  

    Role definition: [CloudFormation](../cfn_templates/core-iam-shared-roles.yaml)

+  **Data engineer**/**ML Engineer**: ❗ The solution doesn't implement this role
  Responsible for:
    - data sourcing
    - data quality assurance
    - data pre-processing
    - Feature engineering
    - develop data delivery pipelines (from the data source to destination S3 bucket where it is consumed by ML model/Data scientist)

    Permission baseline:
    - Data processing services (DMS, AWS Glue ETL, Athena, Kinesis, EMR, DataBrew, SageMaker, SageMaker Data Wrangler)
    - Data locations (S3, Data Lakes, Lake Formation)
    - Databases (RDS, Aurora, Redshift)
    - BI services (Grafana, Quicksight)
    - SageMaker notebooks


A dedicated IAM role is created for each persona/user. For a real-world project we recommend to start with the least possible permission set for a role and add necessary permissions based on your security requirements and functions the role needs to fulfill.

## IAM configuration
The following diagram shows the provisioned IAM roles for personas/users and execution roles for services:

![PoC IAM overview](design/ml-ops-iam.drawio.svg)

More information and examples about the recommended practices and security setup for multi-project and multi-team environments you can find in the blog post [Configuring Amazon SageMaker Studio for teams and groups with complete resource isolation](https://aws.amazon.com/fr/blogs/machine-learning/configuring-amazon-sagemaker-studio-for-teams-and-groups-with-complete-resource-isolation/) on [AWS Machine Learning Blog](https://aws.amazon.com/blogs/machine-learning/).

### Multi-account setup for IAM roles
For this solution we use three AWS Organizations organizational units (OUs) to simulate development, staging, and production environments. The following section describes how the IAM roles should be mapped to the accounts in the OUs.

#### IAM role to account mapping
**DEV account**:
  + All three IAM user roles must be created in the development (data science) account: `DataScienceAdministratorRole`, `DataScienceProjectAdministratorRole`, `DataScientistRole`

  - **DataScienceAdministratorRole**: overall management of data science projects via AWS Service Catalog. Management of the AWS Service Catalog. Deployment of a data science environment (VPC, subnets, S3 bucket) to an AWS account
  - **DataScientistRole**: Data Scientist role within a specific project. Provisioned on per-project and per-stage (dev/test/prod) basis
  - **DataScienceTeamAdministratorRole**: Administrator role within a specific team or environment

### IAM execution roles
The CloudFormation templates provision the following IAM execution roles in the development account:
  + `SageMakerDetectiveControlExecutionRole`: for Lambda function to implement responsive/detective security controls
  + `SCLaunchRole`: for AWS Service Catalog to deploy a new Studio domain
  + `SageMakerExecutionRole`: execution role for the SageMaker workloads and Studio
  + `SageMakerPipelineExecutionRole`: execution role for SageMaker Pipelines
  + `SageMakerModelExecutionRole`: execution role for SageMaker model endpoint, is be created in each of dev, stating and production accounts
  + `SCProjectLaunchRole`: for AWS Service Catalog to deploy project-specific products (such as SageMaker Notebooks)
  + `AmazonSageMakerServiceCatalogProductsUseRole`: for SageMaker CI/CD execution (CodeBuild and CodePipeline)
  + `AmazonSageMakerServiceCatalogProductsLaunchRole`: for SageMaker MLOps project templates deployments via AWS Service Catalog
  + `VPCFlowLogsRole`: optional role for VPC Flow Logs to write logs into a CloudWatch log group

#### Staging and production accounts
You must create the following IAM roles in each of the accounts in the staging and production environments:
+ `ModelExecutionRole`: SageMaker uses this role to run inference endpoints and access the model artifacts during the provisioning of the endpoint. This role must have a trust policy for `sagemaker.amazonaws.com` service
+ `StackSetExecutionRole`: used for CloudFormation stack set operations in the staging and production accounts. This role is assumed by `StackSetAdministrationRole` in the development account
+ `SetupStackSetExecutionRole`: this role is needed for stack set operations for the initial provisioning of the data science environment in multi-account deployment use case

## Multi-account model deployment
To use multi-account ML model deployment with this solution, you have two options how to provide staging and production accounts ids: 
- use AWS Organizations organizational units (OUs)
- use AWS account lists

### Option 1: OU setup for multi-account deployment
This solution can use a multi-account AWS environment setup in [AWS Organizations](https://aws.amazon.com/organizations/). Organizational units (OUs) should be based on function or common set of controls rather than mirroring company’s reporting structure.

If you use an AWS Organization setup option, you must provide **two organizational unit ids** (OU ids) for the staging and production unit and setup the data science account as the **delegated administrator** for AWS Organizations.

Your AWS Organizations structure can look like the following:
```
Root
`--- OU SageMaker PoC
      |--- data science account (development)
      `----OU Staging
            |--- Staging accounts
      `----OU Production
            |--- Production accounts
```

Please refer to the [Deployment section](documentation/deployment.md) for the details how to setup the delegated administrator.

### Option 2: provide account list for multi-account deployment
Use of AWS Organizations is not needed for a multi-account MLOps setup. The same permission logic and account structure can be implemented with IAM cross-account permissions without need for AWS organizations. This solution also works without AWS Organizations setup. You can provide **lists with staging and production AWS account ids** during the provisioning of the data science environment.

Please refer to the [Deployment section](documentation/deployment.md) for the description of corresponding CloudFormation parameters.

### Single-account setup
The solution also implements full MLOps functionality with single-account setup. All examples, workflows and pipelines work in the single (development) data science account. We do not recommend to use a single-account setup for any production use of SageMaker and Studio, but for testing and experimentation purposes it is a fast and cost-effective option to choose.

## Security
see [Security](documentation/security.md)

## MLOps
see [MLOps](documentation/mlops.md)

## Deployment
see [Deployment guide](documentation/deployment.md)

## Clean up
see [Clean up](documentation/clean-up.md)

## Resources
see [Resources](documentation/resources.md)

## Appendixes
see [Appendixes](documentation/appendix.md)

---

Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
SPDX-License-Identifier: MIT-0
