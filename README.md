# Twitter-comprehend, a simple way of monitoring what people say about us

Twitter-comprehend is a python application which searches for tweets containing certain keywords, sends the tweets to the AWS Comprehend service for analysis and finally posts them to a Slack channel for people to read. This should help us 

The application runs on AWS as a lambda function and it is scheduled to run every 5 minutes. Each run it performs a search for new tweets by calling the Twitter [Standard search API](https://developer.twitter.com/en/docs/tweets/search/api-reference/get-search-tweets). To be able to call the API we have created a Twitter app and will use it's API keys as well as access tokens for authorization when making calls to the API. The first time the function is run after it is deployed it will use the query parameters found in the `twitter-query-parameters.txt` file. After calling the API for the first time we are given a `refresh_url` parameter in the response, which will be used the next time the function is run. The `refresh_url` is stored in an S3 bucket named `twitter-comprehend-bucket`.

For each new tweet which is returned from the search API we take the message text and send it to the [AWS Comprehend service](https://aws.amazon.com/comprehend/). Comprehend can extract things such as key phrases, topics and sentiment from a text. For now we are only interested in the sentiment of the message, we want to know whether or not sentences which contain our keyword are positive. So from the response we get from Comprehend we extract the sentiment as well as the confidence of that sentiment. The possible sentiments are Neutral, Positive, Negative and Mixed.

One issue with AWS Comprehend is that most of it's APIs currently only support English and Spanish. This means that when using the sentiment API we have to set the language to English, which leads to our mostly Finnish tweets to be classified incorrectly.

The final part of the application, after fetching the tweets and passing them through Comprehend, is to send them to Slack. To do this we have created a Slack app, as well as a webhook for it. We can then call the webhook url to post to our Slack channel.

## Deployment

The lambda function and other resources are deployed using [Terraform](https://www.terraform.io/). `terraform-settings.tf` defines what will be done when we run `terraform apply`. The script will first install needed python dependencies, then create a zip of the `lambda-function` directory. It will then create the lambda function using that zip file. It gives the lambda function the environment variables it needs, a Cloudwatch event rule for running it every 5 minutes as well as a IAM role with all the needed policies. It also creates the `twitter-comprehend-bucket` S3 bucket and adds the `twitter-query-parameters.txt` file to it.

1. Install [Terraform](https://www.terraform.io/)
2. In project root run `terraform init`
3. Run `terraform apply`, you will be asked for multiple parameters
* `aws_access_key` and `aws_secret_key` Can be found in AWS IAM > Users > Your user > Security credentials
* `access_token`, `access_token_secret`, `api_key` and `api_secret` Are twitter API credentials which can be found [here](https://apps.twitter.com/) > Select your app > Keys and Access Tokens
* `slack_url` Can be found [here](https://api.slack.com/apps) > Select your app > Incoming webhooks > Webhook url
* `environment_name` An environment name of your choosing, will be used as a suffix for AWS resource names
* You can also store these variables in a file named `terrafrom.tfvars` which should be located in the root directory. This way you do not need to enter them each time you run `terraform apply`. The content of the file should be in the following format

```
access_key = "foo"
secret_key = "bar"
```