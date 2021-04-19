import json
import boto3
import time
import sys
ssm = boto3.client("ssm")
clean_up_efs = __import__("clean-up-efs")


sm_domain_id = "d-jl5mj8qgakee"

clean_up_efs.delete_efs(sm_domain_id, delete_vpc = True)
