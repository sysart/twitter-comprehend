import boto3
from botocore.vendored import requests
from requests_oauthlib import OAuth1
import os
import json


def lambda_handler(event, handler):
    print("Fetching new tweets")
    newMessages = get_new_messages()

    print("{} new tweets found, sending to Slack".format(len(newMessages.get('statuses'))))
    for message in newMessages.get('statuses'):
        comprehendResponse = send_to_comprehend(message.get('text'))
        content = "https://twitter.com/{}/status/{}\n{}".format(message.get('user').get('screen_name'),
                                                                message.get('id'), comprehendResponse)

        data = {
            "text": content
        }

        response = requests.post(os.environ['SLACK_URL'], data=json.dumps(data))

    client = boto3.client('s3')

    refreshUrl = newMessages.get('search_metadata').get('refresh_url')
    client.delete_object(Bucket=os.environ['S3_BUCKET'], Key=os.environ['QUERY_PARAMETERS'])
    client.put_object(Body=refreshUrl, Bucket=os.environ['S3_BUCKET'], Key=os.environ['QUERY_PARAMETERS'])


def get_new_messages():
    auth = OAuth1(os.environ['API_KEY'], os.environ['API_SECRET'], os.environ['ACCESS_TOKEN'],
                  os.environ['ACCESS_TOKEN_SECRET'])
    requests.get(os.environ['TWITTER_VERIFICATION_URL'], auth=auth)

    s3 = boto3.resource('s3')
    parameterFile = s3.Object(os.environ['S3_BUCKET'], os.environ['QUERY_PARAMETERS'])
    queryParameters = parameterFile.get()['Body'].read().decode('utf-8')

    response = requests.get(os.environ['TWITTER_URL'] + queryParameters, auth=auth).json()

    return response


def send_to_comprehend(message):
    comprehend = boto3.client(service_name='comprehend', region_name='eu-west-1')
    result = comprehend.detect_sentiment(Text=message, LanguageCode='en')

    sentiment = result['Sentiment'].lower()
    accuracy = "{0:.1f}".format(result['SentimentScore'][sentiment.title()] * 100)

    responseMessage = "Sentiment of this tweet was {} with a probablity of {}%".format(sentiment, accuracy)

    print(responseMessage)

    return responseMessage
