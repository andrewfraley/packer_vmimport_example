# Andy Fraley Feb 2019
# Terraform code for using the amazon-import post-processor
# https://www.packer.io/docs/post-processors/amazon-import.html
# Sets up the VM Import role, S3 bucket, user group, and policies used for importing base images from a workstation

locals {
  name_prefix = "packer"
  users       = [
    "user1@example.com",
    "user2@example.com"
  ]
}

data "aws_caller_identity" "current" {}

# S3 bucket to hold uploaded images
# Packer uploads the ova here first, then invokes ec2 import-image which does the importing from s3
resource "aws_s3_bucket" "bucket" {
  bucket = "${local.name_prefix}-s3-bucket"
  acl    = "private"
}

# We need a group, members of the group, and a policy to grant s3 write access and to allow ec2 import-image
resource "aws_iam_group" "vmimport" {
  name = "${local.name_prefix}-group-vmimport"
}

resource "aws_iam_group_membership" "vmimport" {
  name = "${local.name_prefix}-group-membership-vmimport"
  users = "${local.users}"
  group = "${aws_iam_group.vmimport.name}"
}

# Allow the group to write to the s3 bucket and use ec2 image-import, packer needs some additional stuff like CreateTags
# (Policy used below is more restrictive than https://docs.aws.amazon.com/vm-import/latest/userguide/vmie_prereqs.html)
resource "aws_iam_group_policy" "vmimport" {
  name  = "${local.name_prefix}-policy-vmimport"
  group = "${aws_iam_group.vmimport.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
     {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Resource":[
        "${aws_s3_bucket.bucket.arn}",
        "${aws_s3_bucket.bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CancelConversionTask",
        "ec2:CancelImportTask",
        "ec2:CopyImage",
        "ec2:CreateImage",
        "ec2:CreateTags",
        "ec2:DeregisterImage",
        "ec2:DescribeConversionTasks",
        "ec2:DescribeImageAttribute",
        "ec2:DescribeImportImageTasks",
        "ec2:DescribeImportSnapshotTasks",
        "ec2:DescribeTags",
        "ec2:ImportImage",
        "ec2:ImportSnapshot",
        "ec2:ImportVolume",
        "ec2:ModifyImageAttribute",
        "ec2:RegisterImage"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}



# Role for aws vmimport process to use
# You need to pass the name of this role to the amazon-import post processor
# ie: "role_name": "packer-role-vmimport",
# https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-image-import.html
resource "aws_iam_role" "vmimport_role" {
  name = "${local.name_prefix}-role-vmimport"
  assume_role_policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
      {
         "Effect": "Allow",
         "Principal": { "Service": "vmie.amazonaws.com" },
         "Action": "sts:AssumeRole",
         "Condition": {
            "StringEquals":{
               "sts:Externalid": "vmimport"
            }
         }
      }
   ]
}
EOF
}

# Policy applied to vmimport role
resource "aws_iam_role_policy" "vmimport_role_policy" {
  name = "${local.name_prefix}-policy-vmimport-role"
  role = "${aws_iam_role.vmimport_role.id}"
  policy = <<EOF
{
   "Version":"2012-10-17",
   "Statement":[
      {
         "Effect":"Allow",
         "Action":[
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket"
         ],
         "Resource":[
            "${aws_s3_bucket.bucket.arn}",
            "${aws_s3_bucket.bucket.arn}/*"
         ]
      },
      {
         "Effect":"Allow",
         "Action":[
            "ec2:ModifySnapshotAttribute",
            "ec2:CopySnapshot",
            "ec2:RegisterImage",
            "ec2:Describe*"
         ],
         "Resource":"*"
      }
   ]
}
EOF
}
