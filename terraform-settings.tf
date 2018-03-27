provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.region}"
}

resource "aws_iam_role" "twitter-comprehend-lambda-role" {
  name = "twitter-comprehend-iam-${var.environment_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "s3-full-acceess-role-policy-attach" {
  role = "${aws_iam_role.twitter-comprehend-lambda-role.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "comprehend-readonly-role-policy-attach" {
  role = "${aws_iam_role.twitter-comprehend-lambda-role.name}"
  policy_arn = "arn:aws:iam::aws:policy/ComprehendReadOnly"
}

resource "aws_iam_role_policy_attachment" "cloudwatch-logs-full-access-role-policy-attach" {
  role = "${aws_iam_role.twitter-comprehend-lambda-role.name}"
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

provider "archive" {
  version = "1.0.0"
}

resource "null_resource" "install_dependencies" {
  provisioner "local-exec" {
    command = "pip install --target=${path.root}/lambda-function requests requests_oauthlib"
    interpreter = [
      "PowerShell",
      "-Command"]
  }
}

data "archive_file" "lambda_archive" {
  type = "zip"
  source_dir = "${path.module}/lambda-function/"
  output_path = "${path.root}/twitter-comprehend.zip"
  depends_on = [
    "null_resource.install_dependencies"]
}

resource "aws_s3_bucket" "twitter-comprehend-bucket" {
  bucket = "twitter-comprehend-bucket-${var.environment_name}"
  acl = "private"

  tags {
    Name = "twitter-comprehend-bucket-${var.environment_name}"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_object" "twitter-comprehend-bucket-object" {
  bucket = "${aws_s3_bucket.twitter-comprehend-bucket.id}"
  acl = "private"
  key = "twitter-query-parameters.txt"
  source = "${path.root}/twitter-query-parameters.txt"
}

resource "aws_lambda_function" "twitter-comprehend" {
  filename = "${data.archive_file.lambda_archive.output_path}"
  function_name = "twitter-comprehend-${var.environment_name}"
  role = "${aws_iam_role.twitter-comprehend-lambda-role.arn}"
  handler = "lambda_function.lambda_handler"
  source_code_hash = "${data.archive_file.lambda_archive.output_sha}"
  runtime = "python3.6"
  timeout = 60

  environment {
    variables = {
      SLACK_URL = "${var.slack_url}"
      QUERY_PARAMETERS = "twitter-query-parameters.txt"
      TWITTER_URL = "https://api.twitter.com/1.1/search/tweets.json"
      S3_BUCKET = "${aws_s3_bucket.twitter-comprehend-bucket.bucket}"
      TWITTER_VERIFICATION_URL = "https://api.twitter.com/1.1/account/verify_credentials.json"
      ACCESS_TOKEN = "${var.access_token}"
      ACCESS_TOKEN_SECRET = "${var.access_token_secret}"
      API_KEY = "${var.api_key}"
      API_SECRET = "${var.api_secret}"
    }
  }
}

resource "aws_cloudwatch_event_rule" "every_five_minutes" {
  name = "every-five-minutes-${var.environment_name}"
  description = "Fires every five minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "check_twitter_every_five_minutes" {
  rule = "${aws_cloudwatch_event_rule.every_five_minutes.name}"
  arn = "${aws_lambda_function.twitter-comprehend.arn}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_twitter" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.twitter-comprehend.function_name}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.every_five_minutes.arn}"
}