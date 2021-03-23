import json
import boto3
import tempfile
import zipfile
import uuid

sc = boto3.client("servicecatalog")
code_pipeline = boto3.client('codepipeline')
s3 = boto3.client("s3")

def get_file(artifact, f_name):
    bucket = artifact["location"]["s3Location"]["bucketName"]
    key = artifact["location"]["s3Location"]["objectKey"]

    print(f"{bucket}/{key}")

    with tempfile.NamedTemporaryFile() as tmp_file:
        s3.download_file(bucket, key, tmp_file.name)
        with zipfile.ZipFile(tmp_file.name, 'r') as z:
            return json.loads(z.read(f_name))

def provision_product(product_id, product_name, provisioning_artifact_id, provisioning_parameters):

        r = sc.provision_product(
            ProductId=product_id,
            ProvisioningArtifactId=provisioning_artifact_id,
            ProvisionedProductName=product_name + str(uuid.uuid4()).split("-")[0],
            ProvisioningParameters=provisioning_parameters
        )

        print(r)

def lambda_handler(event, context):
    try:
        job_id = event['CodePipeline.job']['id']
        job_data = event['CodePipeline.job']['data']

        user_param = json.loads(job_data["actionConfiguration"]["configuration"]["UserParameters"])
        data = get_file(job_data["inputArtifacts"][0], user_param.get("FileName"))

        provision_product(data["ProductId"], data["ProvisioningArtifactIds"], data["ProductName"], user_param["ProvisioningParameters"])

        code_pipeline.put_job_success_result(jobId=job_id)
    except Exception as e:
        print(f"exception: {str(e)}")
        code_pipeline.put_job_failure_result(jobId=job_id, failureDetails={'message': str(e), 'type': 'JobFailed'})