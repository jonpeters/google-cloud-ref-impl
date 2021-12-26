from flask import Request, Response
import json
from db import db
from concurrent import futures
from google.cloud import pubsub_v1
from typing import Callable, List
import os
import functions_framework


@functions_framework.http
def entry_point(request: Request):
    method = request.method.upper()

    with db.connect() as conn:
        if method == "GET":
            results = conn.execute("SELECT name FROM items").fetchall()
            results = [result[0] for result in results]
            return Response(json.dumps(results), status=200)
        elif method == "POST":
            publish([request.data.decode("UTF-8")])

    return Response(status=200)


def publish(messages: List[str]):
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(
        os.getenv("GCP_PROJECT"), os.getenv("TOPIC_ID"))
    publish_futures = []

    def get_callback(
        publish_future: pubsub_v1.publisher.futures.Future, data: str
    ) -> Callable[[pubsub_v1.publisher.futures.Future], None]:
        def callback(publish_future: pubsub_v1.publisher.futures.Future) -> None:
            try:
                # Wait 60 seconds for the publish call to succeed.
                print(publish_future.result(timeout=60))
            except futures.TimeoutError:
                print(f"Publishing {data} timed out.")

        return callback

    for message in messages:
        # When you publish a message, the client returns a future.
        publish_future = publisher.publish(topic_path, message.encode("utf-8"))
        # Non-blocking. Publish failures are handled in the callback function.
        publish_future.add_done_callback(get_callback(publish_future, message))
        publish_futures.append(publish_future)

    # Wait for all the publish futures to resolve before exiting.
    futures.wait(publish_futures, return_when=futures.ALL_COMPLETED)
