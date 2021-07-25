import json
import boto3
import uuid
import sys
import time

pp_id = sys.argv[1]
sc = boto3.client("servicecatalog")

print(f"terminating the provisioned product {pp_id}")
print(sc.describe_provisioned_product(Id=pp_id))

r = sc.terminate_provisioned_product(
        ProvisionedProductId=pp_id,
        TerminateToken=str(uuid.uuid4())).get("RecordDetail")

print(r)
time.sleep(5)

record_id = r.get("RecordId")
status = "IN_PROGRESS"
while status == "IN_PROGRESS":
    status = sc.describe_record(Id=record_id).get("RecordDetail").get("Status")
    print(f"waiting for termination of {pp_id} to complete: current status: {status}")
    time.sleep(10)
    
if status not in ["CREATED", "SUCCEEDED"]:
    raise Exception(f"Failed to terminate provisioned product {pp_id}: Status = {status}")
