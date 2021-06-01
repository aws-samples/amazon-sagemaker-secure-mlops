"""Example workflow pipeline script for abalone pipeline.

                                               . -RegisterModel
                                              .
    Process-> Train -> Evaluate -> Condition .
                                              .
                                               . -(stop)

Implements a get_pipeline(**kwargs) method.
"""
import os
import json
import boto3
import sagemaker
import sagemaker.session

from sagemaker.estimator import Estimator
from sagemaker.inputs import TrainingInput
from sagemaker.model_metrics import (
    MetricsSource,
    ModelMetrics,
)
from sagemaker.processing import (
    ProcessingInput,
    ProcessingOutput,
    ScriptProcessor,
)
from sagemaker.sklearn.processing import SKLearnProcessor
from sagemaker.workflow.conditions import ConditionLessThanOrEqualTo
from sagemaker.workflow.condition_step import (
    ConditionStep,
    JsonGet,
)
from sagemaker.workflow.parameters import (
    ParameterInteger,
    ParameterString,
)
from sagemaker.workflow.pipeline import Pipeline
from sagemaker.workflow.properties import PropertyFile
from sagemaker.workflow.steps import (
    ProcessingStep,
    TrainingStep,
)
from sagemaker.workflow.step_collections import RegisterModel
from sagemaker.network import NetworkConfig


BASE_DIR = os.path.dirname(os.path.realpath(__file__))

def get_environment(project_name, ssm_params):
    sm = boto3.client("sagemaker")
    ssm = boto3.client("ssm")

    r = sm.describe_domain(
            DomainId=sm.describe_project(
                ProjectName=project_name
                )["CreatedBy"]["DomainId"]
        )
    del r["ResponseMetadata"]
    del r["CreationTime"]
    del r["LastModifiedTime"]
    r = {**r, **r["DefaultUserSettings"]}
    del r["DefaultUserSettings"]

    i = {
        **r,
        **{t["Key"]:t["Value"] 
            for t in sm.list_tags(ResourceArn=r["DomainArn"])["Tags"] 
            if t["Key"] in ["EnvironmentName", "EnvironmentType"]}
    }

    for p in ssm_params:
        try:
            i[p["VariableName"]] = ssm.get_parameter(Name=f"{i['EnvironmentName']}-{i['EnvironmentType']}-{p['ParameterName']}")["Parameter"]["Value"]
        except:
            i[p["VariableName"]] = ""

    return i

def get_session(region, default_bucket):
    """Gets the sagemaker session based on the region.

    Args:
        region: the aws region to start the session
        default_bucket: the bucket to use for storing the artifacts

    Returns:
        sagemaker.session.Session instance
    """

    boto_session = boto3.Session(region_name=region)

    sagemaker_client = boto_session.client("sagemaker")
    runtime_client = boto_session.client("sagemaker-runtime")
    return sagemaker.session.Session(
        boto_session=boto_session,
        sagemaker_client=sagemaker_client,
        sagemaker_runtime_client=runtime_client,
        default_bucket=default_bucket,
    )

def get_pipeline(
    region,
    project_name=None,
    model_package_group_name="AbalonePackageGroup",
    pipeline_name="AbalonePipeline",
    base_job_prefix="Abalone",
):
    """Gets a SageMaker ML Pipeline instance working with on abalone data.

    Args:
        region: AWS region to create and run the pipeline.
        processing_role: IAM role to create and run processing steps
        training_role: IAM role to create and run training steps
        data_bucket: the bucket to use for storing the artifacts

    Returns:
        an instance of a pipeline
    """

    # Dynamically load environmental SSM parameters - provide the list of the variables to load from SSM parameter store
    ssm_parameters = [
        {"VariableName":"DataBucketName", "ParameterName":"data-bucket-name"},
        {"VariableName":"ModelBucketName", "ParameterName":"model-bucket-name"},
        {"VariableName":"S3KmsKeyId", "ParameterName":"kms-s3-key-arn"},
        {"VariableName":"EbsKmsKeyArn", "ParameterName":"kms-ebs-key-arn"},
    ]

    env_data = get_environment(project_name=project_name, ssm_params=ssm_parameters)
    print(f"Environment data:\n{json.dumps(env_data, indent=2)}")

    security_group_ids = env_data["SecurityGroups"]
    subnets = env_data["SubnetIds"]
    processing_role = env_data["ExecutionRole"]
    training_role = env_data["ExecutionRole"]
    data_bucket = env_data["DataBucketName"]
    model_bucket = env_data["ModelBucketName"]
    ebs_kms_id = env_data["EbsKmsKeyArn"]
    s3_kms_id = env_data["S3KmsKeyId"]

    sagemaker_session = get_session(region, data_bucket)

    if processing_role is None:
        processing_role = sagemaker.session.get_execution_role(sagemaker_session)
    if training_role is None:
        training_role = sagemaker.session.get_execution_role(sagemaker_session)
    if model_bucket is None:
        model_bucket = sagemaker_session.default_bucket()


    print(f"Creating the pipeline '{pipeline_name}':")
    print(f"Parameters:{region}\n{security_group_ids}\n{subnets}\n{processing_role}\n\
    {training_role}\n{data_bucket}\n{model_bucket}\n{model_package_group_name}\n\
    {pipeline_name}\n{base_job_prefix}")

    # parameters for pipeline execution
    processing_instance_count = ParameterInteger(name="ProcessingInstanceCount", default_value=1)
    processing_instance_type = ParameterString(
        name="ProcessingInstanceType", default_value="ml.m5.xlarge"
    )
    training_instance_type = ParameterString(
        name="TrainingInstanceType", default_value="ml.m5.xlarge"
    )
    model_approval_status = ParameterString(
        name="ModelApprovalStatus", default_value="PendingManualApproval"
    )
    input_data = ParameterString(
        name="InputDataUrl",
        default_value=f"s3://{sagemaker_session.default_bucket()}/datasets/abalone-dataset.csv",
    )

    # configure network for encryption, network isolation and VPC configuration
    # Since the preprocessor job takes the data from S3, enable_network_isolation must be set to False
    # see https://github.com/aws/amazon-sagemaker-examples/issues/1689
    network_config = NetworkConfig(
        enable_network_isolation=False, 
        security_group_ids=security_group_ids,
        subnets=subnets,
        encrypt_inter_container_traffic=True)
    
    # processing step for feature engineering
    sklearn_processor = SKLearnProcessor(
        framework_version="0.23-1",
        instance_type=processing_instance_type,
        instance_count=processing_instance_count,
        base_job_name=f"{base_job_prefix}/sklearn-abalone-preprocess",
        sagemaker_session=sagemaker_session,
        role=processing_role,
        network_config=network_config,
        volume_kms_key=ebs_kms_id,
        output_kms_key=s3_kms_id
    )
    
    step_process = ProcessingStep(
        name="PreprocessAbaloneData",
        processor=sklearn_processor,
        outputs=[
            ProcessingOutput(output_name="train", source="/opt/ml/processing/train"),
            ProcessingOutput(output_name="validation", source="/opt/ml/processing/validation"),
            ProcessingOutput(output_name="test", source="/opt/ml/processing/test"),
        ],
        code=os.path.join(BASE_DIR, "preprocess.py"),
        job_arguments=["--input-data", input_data],
    )

    # training step for generating model artifacts
    model_path = f"s3://{model_bucket}/{base_job_prefix}/AbaloneTrain"
    image_uri = sagemaker.image_uris.retrieve(
        framework="xgboost",
        region=region,
        version="1.0-1",
        py_version="py3",
        instance_type=training_instance_type,
    )
    xgb_train = Estimator(
        image_uri=image_uri,
        instance_type=training_instance_type,
        instance_count=1,
        output_path=model_path,
        base_job_name=f"{base_job_prefix}/abalone-train",
        sagemaker_session=sagemaker_session,
        role=training_role,
        subnets=network_config.subnets,
        security_group_ids=network_config.security_group_ids,
        encrypt_inter_container_traffic=True,
        enable_network_isolation=False,
        volume_kms_key=ebs_kms_id,
        output_kms_key=s3_kms_id
    )
    xgb_train.set_hyperparameters(
        objective="reg:linear",
        num_round=50,
        max_depth=5,
        eta=0.2,
        gamma=4,
        min_child_weight=6,
        subsample=0.7,
        silent=0,
    )
    
    step_train = TrainingStep(
        name="TrainAbaloneModel",
        estimator=xgb_train,
        inputs={
            "train": TrainingInput(
                s3_data=step_process.properties.ProcessingOutputConfig.Outputs[
                    "train"
                ].S3Output.S3Uri,
                content_type="text/csv",
            ),
            "validation": TrainingInput(
                s3_data=step_process.properties.ProcessingOutputConfig.Outputs[
                    "validation"
                ].S3Output.S3Uri,
                content_type="text/csv",
            ),
        },
    )

    # processing step for evaluation
    script_eval = ScriptProcessor(
        image_uri=image_uri,
        command=["python3"],
        instance_type=processing_instance_type,
        instance_count=1,
        base_job_name=f"{base_job_prefix}/script-abalone-eval",
        sagemaker_session=sagemaker_session,
        role=processing_role,
        network_config=network_config,
        volume_kms_key=ebs_kms_id,
        output_kms_key=s3_kms_id
    )
    
    evaluation_report = PropertyFile(
        name="AbaloneEvaluationReport",
        output_name="evaluation",
        path="evaluation.json",
    )
    step_eval = ProcessingStep(
        name="EvaluateAbaloneModel",
        processor=script_eval,
        inputs=[
            ProcessingInput(
                source=step_train.properties.ModelArtifacts.S3ModelArtifacts,
                destination="/opt/ml/processing/model",
            ),
            ProcessingInput(
                source=step_process.properties.ProcessingOutputConfig.Outputs[
                    "test"
                ].S3Output.S3Uri,
                destination="/opt/ml/processing/test",
            ),
        ],
        outputs=[
            ProcessingOutput(output_name="evaluation", source="/opt/ml/processing/evaluation"),
        ],
        code=os.path.join(BASE_DIR, "evaluate.py"),
        property_files=[evaluation_report],
    )

    # register model step that will be conditionally executed
    model_metrics = ModelMetrics(
        model_statistics=MetricsSource(
            s3_uri="{}/evaluation.json".format(
                step_eval.arguments["ProcessingOutputConfig"]["Outputs"][0]["S3Output"]["S3Uri"]
            ),
            content_type="application/json"
        )
    )

    """
    There is a bug in RegisterModel implementation
    The RegisterModel step is implemented in the SDK as two steps, a _RepackModelStep and a _RegisterModelStep. 
    The _RepackModelStep runs a SKLearn training step in order to repack the model.tar.gz to include any custom inference code in the archive. 
    The _RegisterModelStep then registers the repacked model.
    
    The problem is that the _RepackModelStep does not propagate VPC configuration from the Estimator object:
    https://github.com/aws/sagemaker-python-sdk/blob/cdb633b3ab02398c3b77f5ecd2c03cdf41049c78/src/sagemaker/workflow/_utils.py#L88

    This cause the AccessDenied exception because repacker cannot access S3 bucket (all access which is not via VPC endpoint is bloked by the bucket policy)
    
    The issue is opened against SageMaker python SDK: https://github.com/aws/sagemaker-python-sdk/issues/2302
    """

    vpc_config = {
        "Subnets":network_config.subnets,
        "SecurityGroupIds":network_config.security_group_ids
    }

    step_register = RegisterModel(
        name="RegisterAbaloneModel",
        estimator=xgb_train,
        model_data=step_train.properties.ModelArtifacts.S3ModelArtifacts,
        content_types=["text/csv"],
        response_types=["text/csv"],
        inference_instances=["ml.t2.medium", "ml.m5.large"],
        transform_instances=["ml.m5.large"],
        model_package_group_name=model_package_group_name,
        approval_status=model_approval_status,
        model_metrics=model_metrics,
        vpc_config_override=vpc_config
    )

    # condition step for evaluating model quality and branching execution
    cond_lte = ConditionLessThanOrEqualTo(
        left=JsonGet(
            step=step_eval,
            property_file=evaluation_report,
            json_path="regression_metrics.mse.value"
        ),
        right=6.0,
    )
    step_cond = ConditionStep(
        name="CheckMSEAbaloneEvaluation",
        conditions=[cond_lte],
        if_steps=[step_register],
        else_steps=[],
    )

    # pipeline instance
    pipeline = Pipeline(
        name=pipeline_name,
        parameters=[
            processing_instance_type,
            processing_instance_count,
            training_instance_type,
            model_approval_status,
            input_data,
        ],
        steps=[step_process, step_train, step_eval, step_cond],
        sagemaker_session=sagemaker_session,
    )
    return pipeline
