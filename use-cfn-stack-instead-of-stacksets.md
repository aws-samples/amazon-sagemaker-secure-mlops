# Use `CloudFormation` provider instead of `CloudFormationStackSet` in CodePipeline deploy action

If you unable to use CloudFormation stack set operations, it's possible to replace stack sets with single CloudFormation stack operation.

## Implementation
One option for this use case is to use a cross-account pipeline role as described in [How do I use CodePipeline to deploy an AWS CloudFormation stack in a different account?](https://aws.amazon.com/premiumsupport/knowledge-center/codepipeline-deploy-cloudformation/)

You must adapt the provided MLOps templates with the following:

1.	Create required cross-account roles in the staging and prod accounts for CodePipeline in the dev account to assume for CloudFormation template deployment as described in the link above
2.	Re-use `StackSetExecutionRole` in the staging and prod accounts for CloudFormation to deploy a SageMaker endpoint CFN template or create a new role
3.	If you create a new CFN execution role, you must provide a correct `SetupRoleName` for  `SetupCrossAccountPermissionsLambda` in [env-main.yaml](https://github.com/aws-samples/amazon-sagemaker-secure-mlops/blob/master/cfn_templates/env-main.yaml) template
4.	Change the CodePipeline deploy actions (both DeployStaging and DeployModelProd) in [project-model-deploy.yaml](https://github.com/aws-samples/amazon-sagemaker-secure-mlops/blob/master/cfn_templates/project-model-deploy.yaml) template:
```yaml
- Name: DeployStaging 
              InputArtifacts:
                - Name: BuildArtifact
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Version: '1'
                Provider: CloudFormation
              Configuration:
			ActionMode: “CHANGE_SET_REPLACE”
			ChangeSetName: “staging”
                StackName: !Sub 'sagemaker-${SageMakerProjectName}-${SageMakerProjectId}-deploy-${GetEnvironmentConfiguration.EnvTypeStagingName}'
                Description: 'SageMaker endpoint in the staging target OU'
                TemplatePath: BuildArtifact::cfn-sm-endpoint.yaml
                TemplateConfiguration: BuildArtifact::staging-config.json
                Capabilities: CAPABILITY_NAMED_IAM
		     RoleArn: <construct a proper ARN with account_id using !GetAtt GetEnvironmentConfiguration.StackSetExecutionRole for role name>

		   roleArn: <cross-account role for CodePipeline from step 1>
              RunOrder: 1
```
5.	Change the format of CFN template parameter [json-files](https://github.com/aws-samples/amazon-sagemaker-secure-mlops/blob/master/mlops-seed-code/model-deploy/staging-config-template.json) because `CloudFormation` action provider uses a different format (Template configuration file)  as specified in [AWS CloudFormation artifacts](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/continuous-delivery-codepipeline-cfn-artifacts.html). You have to change the [`build.py`](https://github.com/aws-samples/amazon-sagemaker-secure-mlops/blob/master/mlops-seed-code/model-deploy/build.py) file in the project seed code (function `prepare_config`) to accommodate for a new file format.
6. Change [env-main.yaml](https://github.com/aws-samples/amazon-sagemaker-secure-mlops/blob/master/cfn_templates/env-main.yaml) to replace the resource type `AWS::CloudFormation::StackSet` for the resources `EnvironmentTargetAccountRolesStackSet` and `EnvironmentVPCStackSet` with `AWS::CloudFormation::Stack` type

## Limitations
Please note, using CloudFormation instead of CloudFormationStackSets is less flexible setup. You control to which accounts the CodePipeline pipeline deploys staging and prod endpoints by **`roleArn`** parameter in the CodePipeline action, rather than by account lists or OU ids. If you change account ids, you need to adjust cross-account roles and other permissions. Furthermore, to deploy SageMaker endpoints to multiple staging and production accounts, you have to create a separate CodePipeline pipeline stage per each individual staging or production account as specified in step 4.
