import json
import boto3

efs = boto3.client("efs")
s3 = boto3.client("s3")

def lambda_handler(event, context):

    if not event:
        return
        
    bucket = event["CodePipeline.job"]["data"]["inputArtifacts"][0]["location"]["s3Location"]["bucketName"]
    key = event["CodePipeline.job"]["data"]["inputArtifacts"][0]["location"]["s3Location"]["objectKey"]

    obj = s3.get_object(Bucket = bucket, Key = key)
    msg = json.loads(obj['Body'].read().decode('utf-8'))
    
    print(f"object body: {msg}")

    sm_domain_id = msg["SageMakerDomainId"]

    print(f"Get EFS file system id(s) for SageMaker domain id {sm_domain_id}")
    fs_id = [
        fs["FileSystemId"] for fs in efs.describe_file_systems()["FileSystems"] 
            if [t["Value"] for t in fs["Tags"] if t["Key"]=="ManagedByAmazonSageMakerResource"][0].split("/")[-1] == sm_domain_id
        ]

    print(f"EFS file system id(s): {fs_id}")

    for id in fs_id:
        print(f"Delete mount targets for EFS file system id: {id}")
        for mt in efs.describe_mount_targets(FileSystemId=id)["MountTargets"]:
            efs.delete_mount_target(MountTargetId=mt["MountTargetId"])
        
        while len(efs.describe_mount_targets(FileSystemId=id)["MountTargets"]) > 0:
            print("Wait until mount targes have been deleted")

        print(f"Delete EFS file system {id}")
        efs.delete_file_system(FileSystemId=id)